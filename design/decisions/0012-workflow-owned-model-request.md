# ADR 0012: One workflow-owned model request retained across its consumers

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** User decisions, 5, 18 and 21 September and 21 and 25 November 2026
- **Amends:** Design Sections 7.3 and 12, ADRs 0004/0005, and F0005/F0006
- **Amended by:** [ADR 0030](0030-engine-owned-model-request.md),
  [ADR 0039](0039-configured-temperatures-and-runaway-resend.md)

## Decision

### Request identity and retained inputs

- A generic request belongs to its current execution, originating compiled YAML step and
  request ordinal. The originating step, which owns identity and retries, is the
  `request-model` step ([ADR 0030](0030-engine-owned-model-request.md)).
- It does not require a fabricated SDD feature, section or task.
- Existing SDD owner variants and purpose validation remain required by operations that
  use those domain authorities; generic ownership cannot stand in for semantic-review,
  repair or clarification authority.

- The originating step declares the repository slot, prompt, result
  schema and optional input resource once. Temperature is configuration-owned
  (§12.5, ADR 0039): the configured `temperature` when the registered model supports
  it, omitted otherwise; workflow temperature parameters reject.
- Native schema output is the only response mode. The catalogue has no `json` member and
  no request, binding, lease or description records a mode. Workflow `response-mode` is
  removed and rejected.
- The request's lifecycle stages run as the fixed stages of the `request-model` step.
  YAML cannot name, reorder or select a stage, and actions never invoke other actions.
- Consumers retain the originating request identity, binding, resources and content;
  they do not rebind to their own step or repeat selection parameters.
- The existing data-dependency compiler proves the required handoff.
- There is no route registry, implicit graph or YAML transport syntax. The one fixed
  kernel stage sequence behind each `request-model` step routes nothing and adds no YAML
  syntax.
- The internal request content contract is `model-request/v1`; it is not a second YAML
  schema resource.
- Task prompt content and the result schema remain explicitly workflow-selected, never
  packaged defaults. [ADR 0014](0014-universal-response-format-guidance.md) adds one
  engine-owned response-framing instruction to every serialized request; it does not
  select task content or a schema.

### Schema and binding selection

- A `request-model` step whose `input` is a native packet resolves the packet's typed
  result-definition ID within the explicitly bound `result-schema` resource once
  ([ADR 0013](0013-workflow-input-reuse.md)). A static or absent `input` sends the whole
  resource.
- A packet that names no definition, or one that is not a complete result definition, fails
  before invocation.
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
- No provider invocation, retry or successor selection occurs during request
  preparation.

- Native sealed pipeline values may omit a byte cap when their owning contract has none.
- Their ownership transfer remains typed and opaque; ordinary copying values and
  contracts with explicit resource bounds retain their existing checks.
- This is not a second request store or a model-call size policy.

### Rejections the stages keep

Each stage rejects, with no partial state published:

- a missing input, a rebinding or a parameter override by a consumer;
- forged deltas, transitions, facts, successors or outcomes;
- missing, stale, foreign or duplicate evidence, including evidence from another
  execution;
- cancellation and allocation failure, each with complete cleanup of leases and owners.

Test-only provider contracts do not enter production composition. An authorization
rejection after an inference preserves the earlier response and its token charge while
closing the invoked request as failed or cancelled.
