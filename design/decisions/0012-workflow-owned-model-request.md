# ADR 0012: Retain one workflow-owned model request across YAML steps

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Explicit user direction
- **Amends:** Design Sections 7.3 and 12, ADRs 0004/0005, and F0005/F0006

## Decision

### Request identity and retained inputs

- A generic request belongs to its current execution, originating compiled YAML step and
  request ordinal.
- It does not require a fabricated SDD feature, section or task.
- Existing SDD owner variants and purpose validation remain required by operations that
  use those domain authorities; generic ownership cannot stand in for semantic-review,
  repair or clarification authority.

- The originating step declares the repository slot, prompt, result
  schema and optional input resource once. The user-approved 2026-09-19 amendment
  in §12.5 makes temperature engine-owned: `0` when the registered model supports
  it, omitted otherwise; workflow temperature parameters reject.
- The user-directed 2026-09-21 amendment makes the required per-model `json`
  boolean in `.sddproviders.json` the sole response-mode selector. `true` selects
  native schema output, `false` prompt-only; registered capabilities still constrain
  support. Workflow `response-mode` is removed and rejected. Binding, preparation,
  correction, authorization and replay retain/verify the selected mode. Full engine
  validation, retries and token accounting remain unchanged.
- Registered identity, binding-validation and request-building operations exchange
  immutable typed pipeline values. The 2026-09-18 user-approved preparation amendment
  also permits `prepare-model-request` to reuse those domain owners and publish
  assignment, validation and preparation together in one runner-validated delta.
- Both forms retain the same originating identity, selected resources and validation
  rules. Failed consolidated preparation publishes no partial state. Detailed
  operations remain available; actions never invoke other actions.
- Consumers retain the originating request identity, binding, resources and content;
  they do not rebind to their own step or repeat selection parameters.
- The existing data-dependency compiler proves the required handoff.
- There is no new route registry, implicit graph or YAML transport syntax.
- The internal request content contract is `model-request/v1`; it is not a second YAML
  schema resource.
- Task prompt content and the result schema remain explicitly workflow-selected, never
  packaged defaults. [ADR 0014](0014-universal-response-format-guidance.md) adds one
  engine-owned response-framing instruction to every serialized request; it does not
  select task content or a schema.

### Schema and binding selection

- [ADR 0013](0013-workflow-input-reuse.md) adds the optional originating parameter
  `result-selection: input` (default `resource`).
- It resolves the native packet's typed result-definition ID within the explicitly bound
  schema resource once.
- Missing packets, selectors or complete result definitions fail before invocation.
- The selector is internal; consumers retain the selected compiled schema through
  validation, retries and completion.
- No model-owned field selects its schema.

- Only a typed slot selects a new model binding.
- A registered consumer of the prepared-request data contract can use its retained
  binding instead.
- Provider capabilities still derive from narrow ports, require policy permission and do
  not follow merely from access to immutable request data.
- A consumer cannot also select another slot, resource or response control for that
  request.

### Execution lifetime

- Request-ledger initialization creates a fresh process-local execution identity.
- The runner owns every value and applies or discards each delta; shared canonical
  identity owners remain alive until their last consumer is destroyed.
- Neither identities nor prepared requests are persisted, restored or reused by a rerun.
- No provider invocation, counting, retry or successor selection occurs during request
  preparation.
- ADRs 0009 and 0011 remain unchanged.

- Native sealed pipeline values may omit a byte cap when their owning contract has none.
- Their ownership transfer remains typed and opaque; ordinary copying values and
  contracts with explicit resource bounds retain their existing checks.
- This is not a second request store or a model-call size policy.

## Operation contracts

YAML selects each operation; request preparation may use either the detailed
operations or the consolidated pure preparation operation. This does not combine
provider authorization, invocation, retries or accounting. The detailed catalogue retains
its input, transition, ownership, rejection and cleanup rules. All integrations
below were recorded as implemented on **2026-09-06**; accounting also retains
its **2026-09-12** protocol-retry and **2026-09-18** validated repair-progress amendments.

The 2026-09-18 user-approved response-admission amendment also permits
`admit-model-response` to combine JSON decoding and selected-schema validation.
It reuses their existing owners and publishes the existing envelope and payload
results together in one runner-validated delta. Detailed operations remain
available. No provider call, lifecycle change, retry, accounting, semantic review
or child-node execution is added; the 512-step expansion limit remains unchanged.

| Operation contract | Detailed rules |
| --- | --- |
| <a id="accounting-integration-implemented-2026-09-06"></a>Accounting | [Contract](model-request-operation-contracts.md#accounting-integration-implemented-2026-09-06) |
| <a id="operation-assignment-integration-implemented-2026-09-06"></a>Operation assignment | [Contract](model-request-operation-contracts.md#operation-assignment-integration-implemented-2026-09-06) |
| <a id="authorization-preparation-integration-implemented-2026-09-06"></a>Authorization preparation | [Contract](model-request-operation-contracts.md#authorization-preparation-integration-implemented-2026-09-06) |
| <a id="request-invocation-state-integration-implemented-2026-09-06"></a>Request invocation-state | [Contract](model-request-operation-contracts.md#request-invocation-state-integration-implemented-2026-09-06) |
| <a id="provider-operation-invocation-state-integration-implemented-2026-09-06"></a>Provider-operation invocation-state | [Contract](model-request-operation-contracts.md#provider-operation-invocation-state-integration-implemented-2026-09-06) |
| <a id="inference-integration-implemented-2026-09-06"></a>Inference | [Contract](model-request-operation-contracts.md#inference-integration-implemented-2026-09-06) |
| <a id="observation-validation-integration-implemented-2026-09-06"></a>Observation validation | [Contract](model-request-operation-contracts.md#observation-validation-integration-implemented-2026-09-06) |
| <a id="json-decoding-integration-implemented-2026-09-06"></a>JSON decoding | [Contract](model-request-operation-contracts.md#json-decoding-integration-implemented-2026-09-06) |
| <a id="payload-schema-validation-integration-implemented-2026-09-06"></a>Payload-schema validation | [Contract](model-request-operation-contracts.md#payload-schema-validation-integration-implemented-2026-09-06) |
| Consolidated response admission | [Contract](model-request-operation-contracts.md#consolidated-response-admission) |
| <a id="provider-operation-completion-integration-implemented-2026-09-06"></a>Provider-operation completion | [Contract](model-request-operation-contracts.md#provider-operation-completion-integration-implemented-2026-09-06) |
| <a id="pre-call-operation-termination-integration-implemented-2026-09-06"></a>Pre-call operation termination | [Contract](model-request-operation-contracts.md#pre-call-operation-termination-integration-implemented-2026-09-06) |
| <a id="logical-request-closure-integration-implemented-2026-09-06"></a>Logical-request closure | [Contract](model-request-operation-contracts.md#logical-request-closure-integration-implemented-2026-09-06) |
| <a id="pre-call-logical-request-closure-integration-implemented-2026-09-06"></a>Pre-call logical-request closure | [Contract](model-request-operation-contracts.md#pre-call-logical-request-closure-integration-implemented-2026-09-06) |

## Acceptance

- Compile and execute arbitrary YAML using the native preparation bindings and test-only
  provider contracts.
- Prove exact identity/resource retention across different steps, missing-input and
  rebinding rejection, malformed SDD owners, cancellation, allocation cleanup and
  isolation between executions.
- Test-only assignment cases also cover duplicate/open operations, both kinds,
  stale/foreign evidence, forged transitions and compiler-permission tampering.
- Authorization cases cover both operation kinds, missing/invalid deadlines, denied
  capability, failed preparation, forged/mismatched deposits and results, duplicate use,
  expiration, cancellation and allocation-failure cleanup.
- Test-only provider contracts do not enter production composition.
- Invocation-state cases also prove exact canonical evidence, the unchanged lease
  deadline, one-use consumption through the existing adapter port, rejected-delta
  atomicity and execution isolation.
- Fake-provider YAML tests also cover one inference call, lease reuse, missing
  dependencies/capabilities, original deadlines, actual-token accounting, failed
  publication, allocation cleanup and execution isolation.
- Observation-validation cases cover exact associations, every stop, provider failures,
  cancellation, invalid UTF-8, cross-execution rejection, missing inputs, parameter
  overrides, allocation cleanup and retained evidence lifetime.
- Token usage is unchanged, and pure validation remains available at budget exhaustion.
- Decoder cases cover valid objects, exact numbers, malformed JSON, duplicate decoded
  keys, trailing content, missing/foreign evidence, source-owner lifetime, allocation
  failure and rejected/cancelled publication.
- Payload-validation cases cover exact compiled schemas, accepted/rejected candidates,
  unchanged upstream outcomes, missing/foreign evidence, overrides, owner lifetime,
  allocation failure, cancelled/rejected publication and validation at token-budget
  exhaustion.
- Detailed/consolidated response admission must preserve selected requests,
  diagnostics, current-authority dependencies, response ownership and actual usage.
  Test exact output-pair contracts, rejected/cancelled atomic publication and
  allocation cleanup, plus independent source/principle correction and repair
  origins through the production runner. The consolidated pair shares one
  publication generation; it does not require identical intermediate generations.
- Completion cases cover exact terminal facts, malformed/schema-invalid content
  independence, missing/foreign/stale/duplicate evidence, forged facts/outcomes,
  allocation/cancellation cleanup, owner lifetime and unchanged usage at exhaustion.
- Request-closure cases cover all evidence-backed reasons/outcomes, unfinished
  operations, missing/foreign/stale/duplicate inputs, forged successors/reasons,
  suppressed failures, compiler/registry rejection, allocation and cancellation cleanup,
  owner lifetime, and closure without a live lease at token exhaustion.
- Production Bedrock is connected through the same retained-request bindings; shared
  fake/adapter and YAML tests prove the production handoff.

- Pre-call termination cases cover both operation kinds, failure/cancellation,
  prepared/missing/foreign/stale/duplicate rejection, forged deltas, no-clock terminal
  fact consumption, prepared-lease checks, allocation and deposited-lease cleanup,
  retained owners, and runtime abandonment without hidden termination.
- Pre-call request-closure cases additionally cover both request statuses, exact
  terminal reasons, unfinished operations, mismatched authorization/terminal facts,
  forged request successors and outcomes, immutable ledger ownership, allocation and
  cancellation cleanup, YAML assertions and compiled-contract tampering.
- An inference-then-authorization-rejection YAML run preserves the earlier response and
  token charge while closing the invoked request as failed or cancelled.
