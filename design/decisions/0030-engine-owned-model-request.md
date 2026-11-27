# ADR 0030: One engine-owned step per model request

- **Status:** Accepted
- **Date:** 2026-10-22
- **Decision authority:** User decisions, 22 and 23 October and 14, 21 and 25 November 2026
- **Amends:** ADRs [0005](0005-workflow-defined-operations.md),
  [0009](0009-atomic-workflow-execution.md), [0011](0011-provider-owned-request-limits.md),
  [0012](0012-workflow-owned-model-request.md),
  [0014](0014-universal-response-format-guidance.md),
  [0016](0016-configured-json-response-composition.md),
  [0019](0019-single-request-debugger.md), [0028](0028-anthropic-messages-provider.md) and
  [0029](0029-bedrock-model-families.md); design.md §1, §3.1, §3.3 (invariant 28); contracts
  §§6.2, 7.3, 9, 12.1, 12.7, 13.4, 14, 21, 22.6, 22.7, 24, 27 and 28 and the
  [model-request operation catalogue](../contracts/model-request-operations.md); F0005,
  F0006, F0007, F0100 and the [E2E harness](../harness/e2e.md) step events
- **Amended by:** [ADR 0033](0033-generic-repair-operations.md),
  [ADR 0039](0039-configured-temperatures-and-runaway-resend.md)

## Context

The stages of one model request (accounting, authorization, lifecycle advances, inference,
observation validation, admission, protocol correction and closure) are the same at every
call site; only `retry-limit` differs. They are engine mechanics, not workflow choices, so
YAML does not author them.

## Decision

### One step per model request

A workflow makes one model request with one step that uses the registered operation
`request-model`. The step declares:

- `slot`;
- `prompt`, and optionally `protocol-prompt`;
- exactly one of `result-schema` (a native packet input selects its result definition within
  it, ADR 0013) or `composition-part` (ADR 0016);
- optional `context`, which may accompany either schema form;
- optional `input` (ADR 0012);
- `retry-limit`, bounded by the operation contract (`0` permits only the initial
  attempt; the operation's one maximum is 3, `model-request-operations.md` "Retry limit").

The step declares no deadline: the provider-operation deadline is the bound catalogue
entry's `requestTimeoutMs` (see "Request deadline"). A `timeout-ms` parameter is rejected.

Every step maps `ok`, `invalid`, `failed` and `cancelled`, and no other outcome.
`request-model` has one contract with those four outcomes and no `advisory` parameter.
Exhausting a request's protocol correction remains a terminal runner rejection, not a YAML
outcome. It names the step and the stage. A stop on the runner's own authority, such as
spending the step ceiling that each execution of the step counts toward once, names its
closed reason ([§6](../contracts/06-pipeline-nodes.md#runner-rejection-reasons)).

The compiler rejects a step that declares both or neither of `result-schema` and
`composition-part`, omits `retry-limit` or sets it above the maximum, leaves an outcome
unmapped, maps `more` or `blocked`, or runs under a policy that does not permit one of the
stages' capabilities.

A definition may still fix repeated parameters and routing, such as `protocol-prompt`,
once in a thin definition-local subgraph (ADR 0013). This ADR adds no workflow-level
default.

### How the step runs

`request-model` is a registered, YAML-selected operation. Its implementation is one fixed,
capability-free kernel orchestrator: the kernel-defined child graph of that registered
operation. Its stage sequence joins ADR 0005's list of fixed engine responsibilities. The
§6.2 private-child-graph rule governs it, as amended below. This coordinator keeps the
orchestrator form beside [ADR 0032](0032-engine-routines.md)'s typed routines and
[ADR 0031](0031-stage-actions.md)'s stage actions. It is YAML-selected, its stages change
runner-owned state (accounting, leases and lifecycle ledgers) the runner must apply per
stage, and the runner must check capabilities per stage binding (§12.1). Sequencing in the
runner itself would give the runner workflow branching (F0006 §9).

The orchestrator coordinates these stages, in this order, through runner-owned child
bindings. This is the one stage list; other documents refer to it.

1. Preparation: request assignment, binding validation and request building.
2. Attempt accounting.
3. Provider-operation assignment.
4. Authorization preparation, using the bound catalogue entry's `requestTimeoutMs`.
5. Request-phase check.
6. Request invocation-state advance, on the initial attempt only, as the phase check
   decides. After a protocol correction only the provider operation advances again.
7. Provider-operation invocation-state advance.
8. Inference.
9. Observation validation.
10. Provider-operation completion.
11. Response admission: decoding and payload-schema validation.
12. Protocol correction, or ADR 0039's runaway re-send, which returns to stage 2.
13. Request closure, or pre-call termination of the operation and then the request.

- **Fixed order.** The order and branches are compiled into the engine and are the same
  for every workflow. YAML cannot reorder, skip, add or name a stage. A former stage
  operation ID rejects at compilation, with no alias.
- **Orchestrator duties only.** The orchestrator branches only on typed stage outcomes.
  It does no model, parsing, validation, state, logging or accounting work itself. A
  preparation rejection invokes no later stage.
- **Runner duties are unchanged.** The runner invokes each stage, validates and applies
  each stage's delta, owns every retry count and accounts actual tokens
  ([ADR 0011](0011-provider-owned-request-limits.md)). It chooses no workflow branch and
  does not police a project-authored lifecycle order.
- **Stages are actions.** Each stage is one action with one responsibility and only its
  own narrow ports. No action invokes another action or selects its
  successor. No stage both invokes and interprets the model, and no stage holds both
  the `model-provider` and `provider-authorization` capabilities.
- **Capabilities.** The step's compiled set is the exact union of its fixed stage
  bindings' port-derived capabilities and their registered accounting permissions, never
  an asserted list.
  The selected workflow policy must permit each of them. The runner checks each stage
  binding against that set before invoking it. Only the composition root constructs the
  stage bindings.
- **One narrow exception to §6.2.** The orchestrator's child graph may contain exactly
  two retries: the request's protocol correction, bounded by the step's declared
  `retry-limit`, and ADR 0039's runaway re-send, bounded at one per attempt outside
  `retry-limit`. It still cannot hold workflow transitions, repair policy, slot or
  resource selection, or a domain stage. Repairs stay workflow branches; each repair is
  its own `request-model` step.
- **One cohesive responsibility: one logical model request.** That is the
  responsibility ADR 0016 requires for consolidation; a lower step count alone would not
  justify it.
- **Nothing hidden.** Every stage runs through a runner-owned child binding of a
  YAML-selected step and emits its own event, so no node runs outside the runner. The
  step makes exactly one request with the resources its YAML declares, so it is not a
  request dispatcher.
- **Stage rules carry over.** The per-operation rules in the
  [operation catalogue](../contracts/model-request-operations.md) stay in force as stage
  rules: inputs, transitions, ownership, rejection, cleanup, token accounting and
  evidence retention.

### Contract variants

One operation may have one registered contract made of closed variants, selected per step
at compile time. This ADR specifies the mechanism, and
[ADR 0033](0033-generic-repair-operations.md)'s four generic repair operations are its only
user.

- **A variant is a complete contract:** outcome set, data effects, side-effect class,
  outcome-association descriptors, repair role and retry authority, the same fields as
  any registered contract. Its type has no defaulted fields, so every variant states
  each one. Nothing is partial or merged from another variant. A variant has one
  association descriptor for every outcome, as ADR 0033's variants use.
- **Selection.** Exactly one closed enum step parameter selects the variant at compile
  time: `owner` for ADR 0033's operations. A value with
  no variant, or a step that leaves out a required selector, rejects at compilation. A
  selector is never a version, alias or compatibility form (ADR 0005). It picks a
  contract variant and grants no policy, scope or defect identity. Whether an operation
  also selects rules from its compiled variant, and how it checks its selector at run
  time, belongs to that operation's ADR: `owner`'s rules and check are in ADR 0033.
  A selector is required; no variant is selected by its absence. A selector may be
  forwarded through a subgraph `{param}`.
- **Registry admission** validates every variant independently, with the same checks as
  any registered contract: a variant that fails a per-contract check rejects although its
  sibling is valid, and two variants with the same selector value reject. Registry-wide
  checks that read every contract cover every variant of every contract: gate-evidence
  exclusivity (including a non-first variant that produces another operation's gate
  evidence key), the gate-issuer check and schema registration. The gate-issuer check
  holds for variants by rejecting an issuer that has variants: a gate issuer must be a
  single-shape operation.
- **The compiler** checks each step against its selected variant alone: outcome mapping,
  data flow, role and association compatibility, and retry authority. Compiled-graph
  validation and registry publication recheck each step against that same variant.
- **The runner and the stage actions** check every delta, outcome, association and
  retry authority against the compiled step's variant, never a union of variants.
- **Scope.** The mechanism carries what ADR 0033 specifies for its variants. It adds no
  run-time selector check of its own and has no operation-specific branch; any check
  against native facts belongs to the operation that uses it.
- **Why this option.** ADR 0033 needs per-owner variants: separate operations would be
  per-owner operations again, and a union contract would lose the per-owner checks. A
  compiler special case is the per-caller branch AGENTS.md forbids.

### Request deadline

The provider-operation deadline is a fact about the model, not the workflow. It bounds a
stalled exchange, and the longest legitimate exchange is the time the model takes to
return its documented maximum output (`maxOutputTokens`, ADR 0011).

- **Where it lives.** Every `.sddproviders.json` model entry, for every provider, declares
  a required positive integer `requestTimeoutMs` in its `config`, beside
  `maxOutputTokens`. The closed catalogue schema rejects a missing, zero, negative,
  fractional, string or unknown field, as it does for `maxOutputTokens`.
- **How it applies.** The authorization stage binds the deadline of the catalogue entry
  that the step's slot selects to every provider operation of that request, including
  protocol corrections. YAML carries no deadline. Selecting a different model for a slot
  brings that model's deadline with it.
- **Enforcement.** The exchange races the network task against
  a timer that polls in slices: each slice reads the run's cancellation status, then the deadline clock, then
  sleeps the smaller of one slice and the time left. A slice is polling granularity, not a
  limit. A cancellation is therefore observed within one slice and the network task is
  joined before the request returns, and a deadline is judged against a fresh clock read,
  so the time a machine is suspended counts. A sent request may still finish and incur
  cost ([ADR 0009](0009-atomic-workflow-execution.md)).
- **Values.** GPT-OSS-20B keeps 180,000 ms; its slowest observed call, a 16,384-token
  runaway, took 74.1 s. Every other entry, including the Claude Haiku 5.5 entry
  (128,000 maximum output tokens), also starts at 180,000 ms.
  A replacement is derived from the measured time the model takes to return its maximum
  output, not from the latency of one ordinary call, and each change is recorded with its
  measurement.
- **Bound.** Catalogue validation rejects a value too large to form a monotonic deadline,
  so an oversized value fails before any request instead of at authorization.
- **Replay.** The request debugger ([ADR 0019](0019-single-request-debugger.md)) replays
  with the captured entry's `requestTimeoutMs`, not a fixed replay deadline, so the
  catalogue is the deadline's one owner.
- **Why.** A deadline set below a model's own maximum-output time turns runaway responses
  into unexplained timeouts. A per-step workflow value would repeat the same guess at
  every call site and apply it to any model the slot selects.

### What stays in YAML

This is the one list; other documents refer to it.

- **Consumers** of an admitted response, which read the retained request as ADR 0012
  describes.
- **Release.** A site's release step chooses what the following steps keep:
  `release-model-request` keeps the input packet for a following request,
  and `release-model-transport` drops it. Release is a workflow
  choice, so it stays an explicit step. Engine-owned release is not adopted; adopting it
  would amend ADRs 0005, 0012, 0030 and 0033 and invariants 25 and 28, and needs its own
  decision.
- **JSON-part retention** after a composition request (`retain-json-part`).
- **Request-ledger initialization** (`build-initial-model-request-identity-ledger`).
- **Repairs**, each its own request.

### Identity, retries and diagnostics

- **Identity.** The `request-model` step is the originating step. Request identity
  stays `(workflowId, workflowVersion, originatingWorkflowStepId)`. ADR 0019's `node_id`
  and `route_id` both name that step, and its action ID records the stage.
- **Retry scopes.** Counting is scoped to the `request-model` step:
  - ordinary requests count by step and immutable assignment;
  - atomic repair requests count by step and native defect key;
  - required dependent requests also bind their pending native parent key (§22.7).
- **Failure location.** Every stage emits its own step event, attributed to the
  originating step with a stable stage name. Reports, the request debugger
  ([ADR 0019](0019-single-request-debugger.md)) and `/evaluate-e2e` name the
  exact stage where a request stopped.
- **Versions.** A change advances each closed contract whose shape changes, with no
  compatibility reader. One user-approved exception: `model-call-evidence` keeps its v1
  and v2 readers, which read those captures (including a recorded `response_mode`) only as
  historical evidence that grants no current authority. Its v3 captures are unreadable.
- **Retained evidence.** Every tool that revalidates retained runs or captures through
  the production registry or an advanced contract (the retained-call replay `e2e-call`,
  the compatibility inspection, the baseline and the frozen binding) rejects those made
  before the change. Measurements that need them run before the change or use raw
  response bytes.

### Token counting is removed

Provider input-token counting, which asks a provider how many input tokens a request would
use before sending it, is removed. There is no `count-model-tokens` step, count operation
kind, capability or CountTokens wire path.

- **Nothing could use it.** ADR 0011 forbids pre-call reservations, capacity prediction
  and local size ceilings, so a count could not gate a request, and no registered model
  contract counts (ADRs 0028 and 0029).
- **The global token count stays.** The workflow token budget, `WorkflowTokenBudgetExceeded`,
  report token totals and per-call usage evidence all come from the actual API-reported
  usage of every inference call (ADR 0011 "Workflow token accounting").
- **Returning it** needs its own decision, made when a workflow needs counting and a
  model supports it.

### Unchanged

- Model calls, prompts, schemas, token usage and the single workflow budget (ADR 0011),
  including actual-usage accounting of every inference call.
- Retry limits and counting scopes, and response admission (ADRs 0006, 0014, 0016 and
  0020).
- Request identity form, `model-request/v1` and retained-request consumers (ADR 0012).
- Atomic execution (ADR 0009) and the 1,024-step ceiling (ADR 0016).

## Consequences

- **Visibility moves to logs.** Request stages have no YAML visibility; logged stage events
  replace it for diagnosis.
- **No behaviour change is claimed.** No change to model behaviour, token cost or run
  reliability is expected or claimed.

## Tests

- **Spy tests for the orchestrator:** stage order; every branch (preparation rejection,
  accounting exhaustion, authorization failure or cancellation, phase `ok`/`more`,
  admission `ok`/`invalid`, and closure); cancellation at each stage; the `retry-limit`
  bound; cleanup on every path.
- **Architecture tests:** no request stage is YAML-addressable; each stage keeps its
  narrow ports; the orchestrator stays capability-free; the runner remains the sole delta
  and accounting owner.
- **Contract variants:** a test contract whose two variants differ in data effects, retry
  authority and repair role passes through the same admission, compiler and runner paths
  that ADR 0033's operations use.

## Not decided here

- The measured replacement for Claude Haiku 5.5's interim 180,000 ms `requestTimeoutMs`.
- Token counting's return, if a workflow and a counting-capable model ever need it.
- Any workflow-level parameter default.
