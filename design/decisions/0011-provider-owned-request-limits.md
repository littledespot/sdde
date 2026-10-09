# ADR 0011: Provider-owned request limits; actual workflow token accounting

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Repeated explicit user direction; no further approval required
- **Scoped amendment:** 2026-10-10, explicitly user-approved optional slot output
  allowance. Other capacity, accounting and retry boundaries remain unchanged.
- **Amends:** Design Sections 3, 9, 12–13, 20, 24, 28 and 31; ADRs 0004–0006;
  F0001, F0005–F0007; and their samples and diagrams

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
- Missing values for these retired contracts are not configuration errors,
  implementation prerequisites or approval questions.

### Optional provider-request output allowance

- `models.slots.<slot>.maxOutputTokens` is an optional positive integer request
  control. Closed decoding checks positivity and native integer representability;
  the registered model contract must support the control.
- When present, send the requested value unchanged. When absent, omit the provider
  field and delegate its default to the provider. Bedrock `InvokeModel` maps the
  control to `max_completion_tokens` through the shared request encoder.
- This is a provider-enforced requested allowance, not an engine capacity ceiling
  or a claim that the response will fit. The API still owns its supported maximum
  and any rejection or stopped-response outcome. SDDE does not predict, reserve,
  clamp, truncate, invent a fallback or add retries because of this control.
- Configuration, validated slot/binding, prepared request and authorization retain
  the same optional control. Correction retains the originating binding; capture
  records its exact presence/value, and replay retains those captured settings
  while validating them against the current binding. Current configuration cannot
  silently replace a captured allowance.
- This amendment does not add an evaluator setting, a YAML size parameter or a
  cumulative budget-derived allowance. Actual workflow accounting below is unchanged.

### Workflow token accounting

- The selected workflow policy's positive `totalModelTokenBudget` is the only cumulative
  model-consumption limit, initialized afresh for each execution.
- Record actual API-reported input plus output tokens after every inference call,
  including retries and stopped output.
- A call may overshoot: retain its full usage, return `WorkflowTokenBudgetExceeded`, and
  prohibit subsequent calls.
- At exact equality the current result may proceed, but subsequent calls cannot.
- Missing usage is not estimated or fabricated; the existing unavailable-usage outcome
  prevents further model calls.
- There is no pre-call token reservation, mandatory counting or budget-derived output
  allowance.

### Retry and safety boundaries

- Retries remain explicit YAML transitions with operation-local `retry-limit`.
- Provider adapters do not retry, truncate, repartition or select fallback calls on
  their own.
- Only complete responses can become untrusted candidates.

- Exact request identity, model-slot authorization, supported controls, schema
  validation, credential protection, cancellation and deadlines remain required.
- Existing configuration/resource-read, logging, command and closed-schema constraints
  keep their separate responsibilities; they cannot be repurposed as model-call size
  ceilings.

## Implementation status and acceptance

- Implemented across operation registration, workflow compilation, binding, request
  construction, authorization, provider observations and decoding.
- The typed model-slot parameter is the sole new-binding selection; ADR 0012 allows
  consumers to retain that request through typed data dependencies.
- Capacity fields, intersections, wire budgets and the static-capacity action/evidence
  are removed.
- Request construction reuses existing identity/schema/control validators, and
  observation validation retains the exact prepared request.
- No replacement capacity service or authority exists.
- Native YAML request preparation is now implemented under ADR 0012, including the
  `invoke-model` binding and unconditional post-call usage accounting.
- Production Bedrock uses the same boundary and accounting, with no additional
  request/response size ceilings.

- Fake-provider and compiler tests cover rejected retired size parameters,
  registration/preparation without capacity configuration, complete valid payloads
  beyond former byte ceilings, preserved size failures/stops and schema rejection.
- Output-allowance tests cover omission, positive values, invalid types/ranges,
  unsupported controls, exact wire projection and changed-control rejection across
  binding, authorization, correction, capture and replay. Provider maxima are not
  encoded as local capacity checks.
- Existing accounting tests cover actual usage, overshoot, subsequent-call prohibition,
  execution isolation and explicit-only retries.
- Architecture tests require the retired capacity fields and local size-failure variants
  to remain absent.
- Configuration/resource capture bounds retain separate negative tests.
