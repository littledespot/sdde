# ADR 0030: One engine-owned step per model request

- **Status:** Accepted amendment, amended 23 October 2026. **Not yet implemented:** the
  engine, the Specify definition and the packaging fixture still use the explicit
  request-lifecycle steps, the four token-count operations and the per-step `timeout-ms`
  until the implementation change lands. Documents that describe those steps carry a
  pointer to this ADR until then.
- **Date:** 2026-10-22; amended 2026-10-23.
- **Decision authority:** The user's instruction on 22 October 2026, "A1, replace the
  subgraph as suggested, update documentations. do not make any code change yet". It
  decides [FIX05](../../fixes/FIX05.md) A1 after a review of the pros and cons of keeping
  the 16-step `model-request-body` subgraph. The user's stated goal is simpler workflow
  YAML.
- **Amendment authority:** On 23 October 2026 the user asked for "the best possible
  solution, remember this is a POC and best outcomes is the primary goal", then directed
  "update docs with" the resulting table of choices. That settles the five choices first
  derived under existing rules; see "Choices settled on 23 October 2026". The user also
  confirmed that the global token count stays, because it is built from actual inference
  usage, not from token counting.
- **Amends:**
  - [ADR 0005](0005-workflow-defined-operations.md): the engine-kernel list, "Sequencing
    and branching are visible in the YAML graph", "must not conceal a second workflow
    graph" and the provider-request fixture sentence, for the stages of one model request;
  - [ADR 0012](0012-workflow-owned-model-request.md): "There is no new route registry,
    implicit graph or YAML transport syntax", "YAML selects each operation … This does
    not combine provider authorization, invocation, retries or accounting", the detailed
    and consolidated operations that "remain available", and its operation-contract table;
  - [ADR 0009](0009-atomic-workflow-execution.md) and
    [ADR 0011](0011-provider-owned-request-limits.md): retries are "explicit YAML
    transitions"; ADR 0011's "Model maximum output" also gains the catalogue's
    `requestTimeoutMs` beside `maxOutputTokens`, and its CountTokens text no longer
    applies;
  - [ADR 0014](0014-universal-response-format-guidance.md): "Explicit input-token
    counting uses the same model-visible projection as inference", because counting is
    removed;
  - [ADR 0016](0016-configured-json-response-composition.md): "Keep detailed operations
    available" and "Detailed operations and distinct request identities remain visible";
  - [ADR 0019](0019-single-request-debugger.md): what `node_id`, `route_id` and the
    action ID name, and its token-count observations;
  - [ADR 0023](0023-advisory-post-generation-review.md): the advisory request outcomes
    as "distinct step occurrences", and its deferred-carrier proof, which now applies
    only to steps declared `role: advisory`;
  - [ADR 0028](0028-anthropic-messages-provider.md) and
    [ADR 0029](0029-bedrock-model-families.md): each catalogue entry's `config` gains a
    required `requestTimeoutMs`, which settles their open per-provider and per-family
    deadline questions; ADR 0029's retired CountTokens registration now has no
    counting path to return to;
  - design.md §1 (property 1 and the "Workflow YAML owns" boundary), §3.1, §3.3
    (invariant 28 and "Response decoding and lifecycle terminalization remain explicitly
    selected operations") and the §32 index;
  - contracts §§6.2, 7.3, 12.1, 12.7, 13.4, 14, 21, 22.6, 22.7, 24, 27 and 28 and the
    [model-request operation catalogue](../contracts/model-request-operations.md);
  - [F0005](../features/F0005-WorkflowDefinitionRegistryService.md),
    [F0006](../features/F0006-LLMProviderInterface.md) (including its count semantics),
    [F0007](../features/F0007-AWSBedrockProvider.md) (including CountTokens),
    [F0100](../features/F0100-SpecWorkflow.md), diagram 16 and the
    [E2E harness](../harness/e2e.md) step events.

  The overall design remains **Proposed design**.

## Context

Every model call in the Specify definition runs through the 16-step `model-request-body`
subgraph. Its steps count the attempt, assign and authorize a provider operation, check
the request phase, advance two lifecycles, invoke the model, validate the observation,
complete the operation, admit the response, build a protocol correction, close or
terminate the request, and close the two advisory stops. Five wrapper subgraphs
(`model-request`, `model-request-with-context`, `support-request`, `composition-request`
and `composition-request-body`) add request preparation and route the result. With the
`release-request` subgraph, this request region is 159 of the definition's 1,159 lines.

- All 16 call sites run exactly the same sequence. Only `retry-limit` differs, and the
  provider-operation `timeout-ms` is one fixed value. (FIX05's figure of 18 model-request
  sites is its count at `b2f10a3`.)
- Subgraphs are definition-local ([ADR 0013](0013-workflow-input-reuse.md)), so every
  further workflow file would carry its own copy.
- Because the sequence is project-authored, the generic runner has to reject every
  wrong ordering of it. A wiring mistake appears only when a run fails, often as a
  rejection without a reason (FIX05 A4).
- Any change to the request lifecycle touches YAML, runner checks, bindings and tests
  together.

None of these steps is a workflow choice. They are engine mechanics that ADRs 0005 and
0012 placed in YAML.

## Decision

### One step per model request

A workflow makes one model request with one step that uses the registered operation
`request-model`. The step declares what today's preparation step and wrappers declare:

- `slot`;
- `protocol-prompt` and `prompt`;
- exactly one of `result-schema`, with the optional `result-selection` of ADR 0013, or
  `composition-part` (ADR 0016);
- optional `context`, which may accompany either schema form;
- `retry-limit`, bounded by the operation contract as today (`0` permits only the
  initial attempt);
- optional `role: advisory`, for a request whose advice may end incomplete (see
  "Advisory role").

The step declares no deadline: the provider-operation deadline is the bound catalogue
entry's `requestTimeoutMs` (see "Request deadline"). A `timeout-ms` parameter is rejected.

The outcome meanings of today's request body are unchanged. Every step maps `ok`,
`invalid`, `failed` and `cancelled`. Only a `role: advisory` step also maps `more` and
`blocked`.

- `more` and `blocked` are the advisory incomplete and advisory protocol-exhausted
  outcomes of ADR 0023. Each advisory step still routes them to
  `propagate-advisory-request-failure` or to a native completion step. The compiler's
  deferred-carrier proof keeps its rules for advisory steps; because one step now carries
  ordinary closure and both advisory carriers, its descriptor becomes per-outcome instead
  of per-step.
- Exhausting the protocol correction of an ordinary or required request remains a
  terminal runner rejection, not a YAML outcome. It names the step and the stage.
  Exhausting an advisory request's correction returns `blocked`, as today.

A definition may still fix repeated parameters and routing, such as `protocol-prompt`
and advisory propagation, once in a thin definition-local subgraph (ADR 0013). This ADR
adds no workflow-level default; its only new YAML is the `role` parameter.

### How the step runs

`request-model` is a registered, YAML-selected operation. Its implementation is one fixed,
capability-free kernel orchestrator: the kernel-defined child graph of that registered
operation. Its stage sequence joins ADR 0005's list of fixed engine responsibilities. The
§6.2 private-child-graph rule governs it, as amended below. This coordinator keeps the
orchestrator form even after [ADR 0032](0032-engine-routines.md) turns the other fixed
engine sequences into typed routines. It is YAML-selected, its stages change runner-owned
state the runner must apply per stage, and the runner must check capabilities per stage
binding.

The orchestrator coordinates these stages, in this order, through runner-owned child
bindings. This is the one stage list; other documents refer to it.

1. Preparation: request assignment, binding validation and request building.
2. Attempt accounting.
3. Provider-operation assignment.
4. Authorization preparation, using the bound catalogue entry's `requestTimeoutMs`.
5. Request-phase check.
6. Request invocation-state advance, on the initial attempt only, as the phase check
   decides.
7. Provider-operation invocation-state advance.
8. Inference.
9. Observation validation.
10. Provider-operation completion.
11. Response admission: decoding and payload-schema validation.
12. Protocol correction, which returns to stage 2.
13. Request closure, pre-call termination of the operation and then the request, or
    advisory completion: the protocol stop or incomplete advice.

- **Fixed order.** The order and branches are compiled into the engine and are the same
  for every workflow. YAML cannot reorder, skip, add or name a stage. A removed stage ID
  rejects at compilation, with no alias.
- **Orchestrator duties only.** The orchestrator branches only on typed stage outcomes.
  It does no model, parsing, validation, state, logging or accounting work itself.
- **Runner duties are unchanged.** The runner invokes each stage, validates and applies
  each stage's delta, owns every retry count and accounts actual tokens
  ([ADR 0011](0011-provider-owned-request-limits.md)). It chooses no workflow branch.
- **Stages are actions.** Each stage is one action with one responsibility and only its
  own narrow ports, as today. No action invokes another action or selects its
  successor. No stage both invokes and interprets the model, and no stage holds both
  the `model-provider` and `provider-authorization` capabilities.
- **Capabilities.** The step's compiled set is the exact union of its fixed stage
  bindings' port-derived capabilities and their registered accounting permissions, never
  an asserted list.
  The selected workflow policy must permit each of them. The runner checks each stage
  binding against that set before invoking it. Only the composition root constructs the
  stage bindings.
- **One narrow exception to §6.2.** The orchestrator's child graph may contain exactly
  one retry: the request's protocol correction, bounded by the step's declared
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

### Advisory role

`role` is an optional, closed step parameter. Its one value is `advisory`, for a request
that ADR 0023 classifies as advisory and lets end with incomplete advice. Ordinary
requests, such as extraction, reconciliation and generation, leave it out.

- **Compiler.** A `role: advisory` step must map `more` and `blocked`, and the
  deferred-carrier proof applies to it unchanged. A step without the role must not map
  them. It carries no advisory carrier, so the proof has nothing to check there.
- **Runtime.** Before the request is invoked, the runner checks the declared role against
  the request's native advisory classification, the sealed advisory evidence ADR 0023
  requires before a failure is deferred. A mismatch in either direction is a terminal
  runner rejection that names the step. So an ordinary step can never produce an advisory
  stop, and a step marked advisory can never be an ordinary request.
- **Effect.** Today's generic wrappers route `more` and `blocked` to
  `propagate-advisory-request-failure` at every call site, including sites whose requests
  are never advisory. Those unreachable mappings and propagation steps go. Which sites are
  advisory follows ADR 0023's classification; the equivalence acceptance below proves the
  marking against today's behaviour.

### Request deadline

The provider-operation deadline is a fact about the model, not the workflow. It bounds a
stalled exchange, and the longest legitimate exchange is the time the model takes to
return its documented maximum output (`maxOutputTokens`, ADR 0011).

- **Where it lives.** Every `.sddproviders.json` model entry, for every provider, declares
  a required positive integer `requestTimeoutMs` in its `config`, beside
  `maxOutputTokens`. The closed catalogue schema rejects a missing, zero, negative,
  fractional or unknown field, as it does for `maxOutputTokens`.
- **How it applies.** The authorization stage binds the deadline of the catalogue entry
  that the step's slot selects to every provider operation of that request, including
  protocol corrections. YAML carries no deadline.
- **Values.** GPT-OSS-20B keeps today's 180,000 ms; its slowest observed call, a
  16,384-token runaway, took 74.1 s. A model without measured latency, such as Claude
  Haiku 5.5 (128,000 maximum output tokens), takes its value from that measurement, from
  the compatibility probe ADR 0028 already requires before live use.
- **Why.** On 21 October 2026 a 60-second deadline, set below GPT-OSS-20B's own maximum
  output time, turned three runaway responses into unexplained timeouts (FIX05 B9). A
  per-step workflow value would repeat the same guess at every call site and apply it to
  any model the slot selects.

### What stays in YAML

This is the one list; other documents refer to it.

- **Consumers** of an admitted response, which read the retained request as ADR 0012
  describes. `reuse-specification-review` consumes the same selection contract as the
  `request-model` step that may follow it; one parameter owner serves both.
- **Release.** A site's release step chooses what the following steps keep:
  `retire-model-request` keeps the input packet for a following request,
  `retire-model-transport` and `retire-model-input` drop it, and
  `retire-advisory-protocol-transport` follows an advisory protocol stop. Release is a
  workflow choice, so it stays an explicit step.
- **Advisory routing:** `propagate-advisory-request-failure` and the native advisory
  stop steps, at each `role: advisory` step that routes `more` or `blocked`.
- **JSON-part retention** after a composition request (`retain-json-part`).
- **Request-ledger initialization** (`build-initial-model-request-identity-ledger`).
- **Repairs**, each its own request.

### Identity, retries and diagnostics

- **Identity.** The `request-model` step is the originating step. Request identity
  stays `(workflowId, workflowVersion, originatingWorkflowStepId)`. ADR 0019's `node_id`
  and `route_id` both name that step, and its action ID records the stage.
- **Retry scopes carry over.** Only the compiled operation changes, to the
  `request-model` step:
  - ordinary requests count by step and immutable assignment;
  - atomic repair requests count by step and native defect key;
  - required dependent requests also bind their pending native parent key (§22.7).
- **Failure location.** Every stage still emits its own step event, attributed to the
  originating step with a stable stage name. Reports, the request debugger
  ([ADR 0019](0019-single-request-debugger.md)) and `/evaluate-e2e` can still name the
  exact stage where a request stopped.
- **Versions.** Compiled step IDs change. The implementation advances each closed
  contract whose shape changes, with no compatibility reader, and names which ones. The
  candidates are `model-request-debug`, `prompt-columns`, `e2e-step-event` and
  `specification-state`'s persisted extraction contract. Persisted extraction contracts
  made before the change no longer match; that is the existing typed outcome for any
  workflow change.
- **Retained evidence.** If a contract advances, runs and captures made before the change
  can't be read by the new build. Measurements that need them, such as FIX05 W4's replay
  of retained captures, run before the change or use raw response bytes.

### Token counting is removed

Provider input-token counting, which asks a provider how many input tokens a request would
use before sending it, is removed. There is no `count-model-tokens` step.

- **Nothing uses it.** No shipped workflow, test fixture or packaging fixture runs a count
  operation. No registered model can count: the Anthropic contract and every Bedrock
  family register no CountTokens (ADRs 0028 and 0029).
- **Nothing could use it.** ADR 0011 forbids pre-call reservations, capacity prediction
  and local size ceilings, so a count could not gate a request.
- **The global token count stays.** The workflow token budget, `WorkflowTokenBudgetExceeded`,
  report token totals and per-call usage evidence all come from the actual API-reported
  usage of every inference call (ADR 0011 "Workflow token accounting"). Counting never
  fed them.
- **Returning it** needs its own decision, made when a workflow needs counting and a
  model supports it.

### Removal

With no compatibility form (AGENTS.md), the implementation removes:

- the YAML registration of every operation whose only job is one stage of a model
  request or token count, detailed or consolidated. That includes
  `prepare-model-request`, `admit-model-response`, the 15 other steps of
  `model-request-body`, the detailed preparation and decoding operations the packaging
  fixture uses, and the four count operations;
- their application bindings as YAML operations, their registry entries and the runner
  checks that police their YAML ordering;
- the body and wrapper subgraphs in the Specify definition, and the explicit request
  steps in the [packaging fixture](../../test/packaging/fixtures/provider-request/provider-request.workflow.yaml);
- the tests that pin YAML registration or YAML ordering of the removed operations;
- the whole token-count path: the count operations and their actions, bindings and
  registry entries, the count branches of provider-operation assignment, authorization,
  invocation, observation, completion and accounting, the `input_token_count` operation
  kind and capability, the exact-token-counter capability and its failure cause where
  nothing else uses them, Bedrock's CountTokens encoding and decoding, the count fixtures
  and the tests of all of these;
- the `timeout-ms` parameter of authorization preparation, and every per-step deadline in
  the Specify definition, the packaging fixture and the smoke test.

The inference stage actions and their unit tests stay, including ADR 0012's negative
cases: forged deltas, stale or foreign evidence, cancellation and allocation cleanup.

### Unchanged

- Model calls, prompts, schemas, token usage and the single workflow budget (ADR 0011),
  including actual-usage accounting of every inference call.
- Every deadline value in use today: each GPT-OSS-20B request keeps 180,000 ms.
- Retry limits and counting scopes, advisory completion and incomplete advice
  (ADR 0023), and response admission (ADRs 0006, 0014, 0016 and 0020).
- Request identity form, `model-request/v1` and retained-request consumers (ADR 0012).
- Atomic execution (ADR 0009) and the 1,024-step ceiling (ADR 0016).

## Choices settled on 23 October 2026

On 22 October these five choices were derived from existing rules and awaited the user's
confirmation. On 23 October the user directed the best option for each, for a proof of
concept whose primary goal is the best outcome. Two were kept as derived and three
changed:

| Choice | Derived on 22 October | Settled on 23 October | Why |
| --- | --- | --- | --- |
| 1. Form | Kernel orchestrator | **Kept** | The only form that keeps the engine's core guarantees |
| 2. Token counting | Rebuild as `count-model-tokens`, contract deferred | **Removed** | Nothing can use it |
| 3. Deadline | `timeout-ms` on every request step | **Moved to each catalogue entry** as `requestTimeoutMs` | It depends on the model, not the workflow |
| 4a. Release | Stays an explicit YAML step | **Kept** | It has to run after workflow-specific consumers |
| 4b. Advisory routing | Every step maps all six outcomes | **Only `role: advisory` steps map `more` and `blocked`** | Removes unreachable mappings from most sites |

1. **Form: a fixed kernel orchestrator with runner-owned child bindings.** The request
   stages change runner-owned state (accounting, leases and lifecycle ledgers) that the
   runner must apply stage by stage. The split between invoking and interpreting the
   model, and between the model and authorization capabilities, must be checked by the
   runner per binding (§12.1). A single action, including an
   [ADR 0031](0031-stage-actions.md) stage action, can't give either, and neither can an
   [ADR 0032](0032-engine-routines.md) routine. Sequencing in the runner itself would give
   the runner workflow branching (F0006 §9).
2. **Token counting is removed** rather than rebuilt; see "Token counting is removed". A
   rebuilt count step would be a lifecycle with no caller and no capable model.
3. **The deadline moves to the catalogue;** see "Request deadline". It is a model fact
   beside `maxOutputTokens`, and the B9 timeouts came from a deadline set below one
   model's maximum output time. This settles the per-provider and per-family deadline
   questions that ADRs 0028 and 0029 left open.
4. **Release stays an explicit YAML step** (4a), because sites choose different
   retirements and a release must follow the request's workflow-specific consumers.
   Engine-owned release needs the compiler to derive each request's lifetime, and stays a
   separate question.
5. **Advisory routing stays at each advisory call site** (4b), because ADR 0023 requires
   per-site propagation or native completion. It applies only to steps declared
   `role: advisory`; see "Advisory role".

## Consequences

- **The request region goes.** The 159-line request region, including the 61-line body,
  leaves the Specify definition, and later workflow files don't copy it.
- **The net YAML saving grows.** The 22 October estimate was about 35–90 lines (3–8%) of
  the Specify definition, because each call site still routed `more` and `blocked` and
  declared `protocol-prompt` and `timeout-ms`. Ordinary sites now route neither advisory
  outcome and need no propagation steps, and no site declares a deadline, so the saving
  is larger. The implementation measures it.
- **Deadlines follow the model.** Selecting a different model for a slot brings that
  model's deadline with it; no workflow edit is needed.
- **Less engine code.** The token-count path, the count operation kind and Bedrock's
  CountTokens wire code go, with their tests.
- **Most of the remaining YAML size is outside this decision.** Of the current 283 steps,
  152 only pass `ok` to the next step and `failed` to the end (FIX05 §4 counted 157 of
  282 at `b2f10a3`). FIX05 A2 and W3 address those.
- **The runner stops policing lifecycle order.** It no longer checks project-authored
  orderings of the lifecycle; one fixed, spy-testable orchestrator runs it.
- **Visibility moves to logs.** Request stages lose YAML visibility; logged stage events
  replace it for diagnosis.
- **No behaviour change is claimed.** No change to model behaviour, token cost or run
  reliability is expected or claimed.

## Acceptance

All offline. The change makes no model call.

- **Freeze first.** Before the subgraph is removed, record today's outcomes, retained
  evidence, retry counts and token accounting across the integration scenario matrix,
  and the production-admission results of retained raw response bytes.
- **Equivalence.** `request-model` must reproduce those frozen results. That includes:
  - protocol correction and retry exhaustion;
  - both advisory stops;
  - budget exhaustion and provider failure;
  - pre-call termination and cancellation;
  - an inference-then-authorization rejection.
- **Spy tests for the orchestrator:**
  - stage order;
  - every branch: accounting exhaustion, authorization failure or cancellation, phase
    `ok`/`more`, admission `ok`/`invalid`/`more`, and closure;
  - cancellation at each stage;
  - the `retry-limit` bound;
  - cleanup on every path.
- **Phase check.** After a protocol correction, only the provider operation advances
  again; the request lifecycle advances once.
- **Retry scopes.** Separate cases for an ordinary request, an atomic repair request
  (defect-keyed) and a required dependent request (parent-bound).
- **Counting removed.** No count operation, operation kind, capability, CountTokens wire
  path, fixture or test remains. Workflow token accounting reproduces the frozen totals
  from inference usage alone.
- **Advisory role:**
  - a `role: advisory` request whose native classification is advisory reproduces both
    advisory stops;
  - an ordinary step whose request is classified advisory, and a `role: advisory` step
    whose request is ordinary, each end in a terminal runner rejection that names the
    step, before invocation.
- **Request deadline:**
  - accepted: catalogue entries of each provider with a positive integer
    `requestTimeoutMs`;
  - rejected: a missing, zero, negative, fractional or string `requestTimeoutMs`;
  - the authorization stage binds the selected entry's value to every provider
    operation of the request, including protocol corrections, and two slots bound to
    entries with different values get different deadlines;
  - a provider operation past its deadline keeps today's timeout outcome and usage
    rules.
- **Compiler cases:**
  - accepted: a valid request step with each schema form, with and without `context`,
    with and without `role: advisory`;
  - rejected: both or neither of `result-schema` and `composition-part`;
  - rejected: a missing `retry-limit`, or any `timeout-ms` parameter;
  - rejected: an unknown `role` value;
  - rejected: an unmapped outcome, including `more` or `blocked` on a `role: advisory`
    step;
  - rejected: `more` or `blocked` mapped on a step without `role: advisory`;
  - rejected: `more` or `blocked` routed to success, or to a model-call or publication
    step, before propagation or native completion;
  - rejected: a removed stage ID, or any attempt to name a stage;
  - rejected: a policy that does not permit one of the stages' capabilities.
- **Reports** name the stage where a request stopped.
- **Architecture tests:**
  - no request stage is YAML-addressable;
  - each stage keeps its narrow ports;
  - the orchestrator stays capability-free;
  - the runner remains the sole delta and accounting owner.
- **Build checks.** `zig build verify` and the clean packaged-executable smoke test pass.
- **Measure.** The change records the Specify definition's lines and steps, and the files
  it touches, before and after (FIX05 A2's measure).

## Not decided here

- Whether the engine should also release a request after its consumers, removing the
  per-site release steps. That changes ADR 0012's retained-request handoff, needs the
  compiler to derive each request's lifetime, and needs its own decision.
- Claude Haiku 5.5's `requestTimeoutMs` value, which waits for measured latency.
- Token counting's return, if a workflow and a counting-capable model ever need it.
- Any workflow-level parameter default. FIX05 A2 and W3 are decided separately, in
  [ADR 0031](0031-stage-actions.md) and [ADR 0033](0033-generic-repair-operations.md).
