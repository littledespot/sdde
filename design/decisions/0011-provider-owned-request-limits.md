# ADR 0011: Provider-owned request limits; actual workflow token accounting

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Repeated explicit user direction; no further approval required
- **Amends:** Design Sections 3, 9, 12–13, 20, 24, 28 and 31; ADRs 0004–0006;
  F0005–F0007; and their samples and diagrams

## Decision

The called provider API owns its request, response and context-size limits.
SDDE does not impose additional engine-, operation-, slot- or model-contract
byte/token ceilings on model calls. It does not predict whether a request or
response will fit, narrow a request to a local ceiling, or reject a call because
an estimated input or output is too large. Provider rejections and stopped
responses are normalized, recorded safely and propagated as typed outcomes.

There are no model-call `input-bytes`, `output-bytes`, `input-tokens` or
`output-tokens` YAML parameters, capacity-intersection contracts, receive/wire
byte budgets, serialized-size proofs or static-capacity gates. Renaming these
restrictions as memory safety, transport budgets or provider-contract facts
does not make them permitted. Missing values for these retired contracts are
not configuration errors, implementation prerequisites or approval questions.

The selected workflow policy's positive `totalModelTokenBudget` is the only
cumulative model-consumption limit, initialized afresh for each execution.
Record actual API-reported input plus output tokens after every inference call,
including retries and stopped output. A call may overshoot: retain its full
usage, return `WorkflowTokenBudgetExceeded`, and prohibit subsequent calls.
At exact equality the current result may proceed, but subsequent calls cannot.
Missing usage is not estimated or fabricated; the existing unavailable-usage
outcome prevents further model calls. There is no pre-call token reservation,
mandatory counting or budget-derived output allowance.

Retries remain explicit YAML transitions with operation-local `retry-limit`.
Provider adapters do not retry, truncate, repartition or select fallback calls
on their own. Only complete responses can become untrusted candidates.

Exact request identity, model-slot authorization, supported controls, schema
validation, credential protection, cancellation and deadlines remain required.
Existing configuration/resource-read, logging, command and closed-schema
constraints keep their separate responsibilities; they cannot be repurposed
as model-call size ceilings.

## Implementation status and acceptance

Implemented across operation registration, workflow compilation, binding,
request construction, authorization, provider observations and decoding. The
typed model-slot parameter is the sole new-binding selection; ADR 0012 allows
consumers to retain that request through typed data dependencies. Capacity fields,
intersections, wire budgets and the static-capacity action/evidence are removed.
Request construction reuses existing identity/schema/control validators, and
observation validation retains the exact prepared request. No replacement
capacity service or authority exists. Native YAML request preparation is now
implemented under ADR 0012. Production YAML model-call integration
and the real Bedrock adapter remain separate work.

Fake-provider and compiler tests cover rejected retired size parameters,
registration/preparation without capacity configuration, complete valid payloads
beyond former byte ceilings, preserved size failures/stops and schema rejection.
Existing accounting tests cover actual usage, overshoot, subsequent-call
prohibition, execution isolation and explicit-only retries. Architecture tests
require the retired capacity fields and local size-failure variants to remain
absent. Configuration/resource capture bounds retain separate negative tests.
