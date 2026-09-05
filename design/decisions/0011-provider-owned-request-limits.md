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

This amendment changes documentation, not code. Existing capacity fields,
intersections and capacity-only checks are legacy implementation to remove.
Preserve binding/schema/control validation through its existing owners rather
than introducing another capacity service or authority.

Tests must reject retired size parameters, prove registration/preparation needs
no capacity configuration, accept complete valid payloads beyond former byte
ceilings, preserve provider-reported size failures/stops, account reported usage
including overshoot, prohibit subsequent calls at or above budget, and prove
execution isolation and explicit-only retries.
