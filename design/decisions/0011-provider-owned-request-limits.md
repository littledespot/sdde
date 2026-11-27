# ADR 0011: Provider-owned request limits; actual workflow token accounting

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** User decisions, 5 September 2026 and 15, 17, 18 and 25 October
  2026
- **Amends:** Design Sections 3, 9, 12–13, 17, 20, 22, 24, 28 and 31; ADRs 0004–0006;
  F0001, F0005–F0007
- **Amended by:** [ADR 0028](0028-anthropic-messages-provider.md),
  [ADR 0030](0030-engine-owned-model-request.md),
  [ADR 0039](0039-configured-temperatures-and-runaway-resend.md)

## Decision

### Provider-owned per-call limits

- The called provider API owns its request, response and context-size limits.
- SDDE does not impose additional engine-enforced byte/token capacity ceilings on
  model calls through operations, slots, model contracts or transport.
- It does not predict whether a request or response will fit, narrow a request to a
  local ceiling, or reject a call because an estimated input or output is too large.
- Provider rejections and stopped responses are normalized, recorded safely and
  propagated as typed outcomes.

- There are no model-call `input-bytes`, `output-bytes`, `input-tokens` or
  `output-tokens` YAML parameters, capacity-intersection contracts, receive/wire byte
  budgets, serialized-size proofs or static-capacity gates.
- Renaming these restrictions as memory safety, transport budgets or provider-contract
  facts does not make them permitted.
- Missing values for these contracts are not configuration errors, implementation
  prerequisites or approval questions.
- No per-family record cardinality cap exists.

### No output-token allowance

A requested allowance truncates output and degrades results, so SDDE never sends one
below the model's documented maximum (see "Model maximum output").

- No slot, model contract, binding, prepared request, correction or replay can
  narrow the output maximum. The provider catalogue (and the grader's evaluator
  configuration) is the stated authority for that maximum and must record the
  model's documented value; the engine does not verify it against the provider.
- The closed configuration rejects `models.slots.<slot>.maxOutputTokens`.
- Request descriptions have no allowance field; engine readback and replay reject a
  description carrying one, as they do older description versions (ADR 0019). Older
  captures stay historical evidence, read only by explicit historical readers, with no
  current authority. Frozen calibration settings likewise gain no current binding
  authority by substitution.
- The model's own maximum is the only output ceiling. When a provider stops a
  response for any non-candidate reason, including that maximum, the runner logs
  `model.provider_stopped` at warning level with the exact stop reason. Actual usage
  is still accounted, and the typed outcome is unchanged. SDDE does not clamp,
  truncate or invent a fallback because of a stop. Its one retry is
  [ADR 0039](0039-configured-temperatures-and-runaway-resend.md)'s re-send after an
  `output_limit` stop; other stops are never retried.

### Model maximum output

A provider may apply a default smaller than a model's maximum when a request omits the
output maximum, so omission is itself a hidden limit.

- Each entry in the provider catalogue, for every provider, records the model's
  documented maximum output as `providers[].models[].config.maxOutputTokens`: required,
  positive and exact, with no default, runtime lookup, clamp or fallback.
- Every catalogue entry also declares a required positive `requestTimeoutMs`: the
  provider-operation deadline, sized to the time the model takes to return this maximum
  ([ADR 0030](0030-engine-owned-model-request.md)).
- The frozen semantic-simplicity protocol records the same maximum and the deadline as
  `request_timeout_ms`; its binding checks reject a request or description carrying any
  other value.
- Every inference request sends that value unchanged as the provider's output maximum
  (`inferenceConfig.maxTokens` for Bedrock Converse, `max_tokens` for Anthropic
  Messages). All slots selecting the entry share it, and no slot, binding or request
  can narrow it.
- The development grader's `evaluation-config/v2` records its judge model's
  documented maximum as `max_output_tokens`, sent the same way.
- Request descriptions record the value in their provider configuration, so replay
  sends the same request.
- A value the provider rejects is a typed provider rejection. A stop at the
  maximum is still logged as `model.provider_stopped`.

### Workflow token accounting

There is one total limit per execution, initialized freshly for every execution. It
covers all model work, with no pool or allowance per purpose.

- **The project configuration owns the budget.** `.sddtoolkit.json` has a required root
  member `workflowTokenBudget`: an integer from 1 to 4,294,967,295, the u32 range that
  the catalogue's integer limits use. There is no engine default.
  - The closed configuration type decodes it once at bootstrap through the shared
    positive-integer rule (`positive_json_integer.zig`), which the catalogue's
    `maxOutputTokens` and `requestTimeoutMs` also use. A missing, zero, negative,
    fractional, exponent, quoted, null, duplicate or out-of-range value fails as
    `ENGINE_CONFIG_PARSE_ERROR`.
  - It sits at the root, not under `models`, so model-slot consumers don't depend on a
    setting they never read.
  - The composition root passes the decoded value to the workflow pipeline runner, which
    starts that execution's token ledger from it.
  - Workflow policy and compiled graphs don't carry it. Policy profiles keep only their
    capabilities and terminal outcomes, a configuration change is never a change to a
    bound workflow graph, and the runner's policy cross-check compares capabilities only.
  - Specification and workflow state don't store the budget. The E2E report's
    `token_accounting.total_budget` records the configured value, and the baseline
    harness reads the budget from the bootstrapped configuration.
- Record actual API-reported input plus output tokens after every inference call,
  including retries and stopped output, exactly once against that total.
- For Converse, normalize input usage as `inputTokens + cacheReadInputTokens +
  cacheWriteInputTokens` (absent optional cache counters are zero), then add
  `outputTokens`. Check arithmetic and reported `totalTokens`; invalid usage is
  unavailable for accounting and remains a fatal native validation failure. This follows the
  [AWS cache accounting contract](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html).
- Any inference call may overshoot: retain its full usage, return
  `WorkflowTokenBudgetExceeded`, and prohibit further model calls globally. At exact equality the
  admitted current result may proceed, but no further model call may start.
- Missing usage is never estimated or fabricated. It prohibits further model
  calls and retains its ordinary workflow failure.
- No pre-call token reservation, mandatory counting, capacity prediction,
  budget-derived output allowance or per-class usage subtotal exists. Trusted association,
  native validation, security, cancellation, deadline, logging and operational failures
  remain blocking.

### Retry and safety boundaries

- A request's protocol correction runs inside its `request-model` step under that step's
  declared `retry-limit` ([ADR 0030](0030-engine-owned-model-request.md)). Every other
  retry is an explicit YAML transition with an operation-local `retry-limit`. The one
  further engine-owned retry is
  [ADR 0039](0039-configured-temperatures-and-runaway-resend.md)'s runaway re-send.
- Provider adapters do not retry, truncate, repartition or select fallback calls on
  their own.
- Only complete responses can become untrusted candidates. A provider `output_limit` is
  a typed non-candidate stop: partial text never becomes a candidate, is never salvaged,
  and receives no protocol correction.

- Exact request identity, model-slot authorization, supported controls, schema
  validation, credential protection, cancellation and deadlines remain required. The
  typed model-slot parameter is the sole new-binding selection.
- Existing configuration/resource-read, logging, command and closed-schema constraints
  keep their separate responsibilities; they cannot be repurposed as model-call size
  ceilings.
