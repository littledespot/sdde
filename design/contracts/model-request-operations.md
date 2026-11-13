# Model-request operation contracts

Detailed contracts for the explicit YAML model-request operations governed by
[ADR 0012](../decisions/0012-workflow-owned-model-request.md).

> **[ADR 0030](../decisions/0030-engine-owned-model-request.md) is implemented.** These
> operations are not YAML-selectable: each request-lifecycle entry below is a fixed **stage**
> of one `request-model` step, a native binding the registry holds under that step's entry, and a
> definition that names a stage's ID fails to compile. A capability-free kernel orchestrator runs
> the stages in the order ADR 0030 lists, through runner-owned child bindings. That list also
> includes the request-phase check, which decides whether the request lifecycle advances
> (initial attempt only). The decode and payload-schema operations are one stage,
> `admit-model-response`.
>
> Every rule below still applies to its stage: inputs, transitions, ownership, rejection,
> cleanup and accounting. Read "explicit step", "YAML selects" and "explicit YAML retry" as
> that stage within the one step. `retry-limit` is a parameter of the `request-model` step,
> which declares no deadline. Retry authority names that step instead of the accounting step; ordinary,
> atomic-repair and dependent counting scopes are unchanged. Correction and closure stay
> distinct stages. Retirement (release) stays an explicit YAML step.

## The `request-model` step's data contract

This is the one statement of what the step requires, leaves and drops; other documents point here.
The owner in code is `src/domain/model_request_kernel.zig`.

- **Requires** the request-identity ledger. **Optional**: `model_input_packet`, `json_composition`.
- **Replaces** the request-identity ledger with the successor the stages publish.
- **Produces and leaves current** the four records a step outside the kernel reads:
  `prepared_model_request`, `accounted_model_attempt`, `terminal_provider_operation` and
  `model_payload_schema_result`. With the ledger, these are the five kept keys.
- **Outcomes**: `ok`, `invalid`, `failed`, `cancelled`, each mapped by the workflow.
- **Per-outcome rule.** The runner ends every step with the same engine-owned invalidation of the
  internal keys that are present, whatever the outcome, and the kept keys the stages had
  published by then stay current on every outcome (a request that stops before a stage
  publishes a kept key has none). The internal keys are `assigned_model_request`, `validated_model_request`,
  `assigned_provider_operation`, `invoked_provider_operation`, `provider_authorization_result`,
  `provider_invocation_result`, `provider_invocation_validation_result` and
  `model_envelope_result`. They exist only between stages; no YAML step can require one.
- **Evidence retention.** `provider_authorization_result`, `model_envelope_result`,
  `provider_invocation_result` and `model_payload_schema_result` are recorded-retention keys, like
  `provider_invocation_validation_result`. Ending the step drops the first three from the current
  envelope, and a correction replaces the payload result; the E2E harness reads every attempt's
  evidence from the recorded history, so a corrected or re-sent request that ends `ok` still reports
  each earlier provider stop, protocol rejection or schema rejection with its own call and origin.
- **Allowance.** The step counts once toward the step ceiling. Its stages are bounded by
  2 x (1 + `retry-limit`) provider calls: each attempt, correction or not, plus its one runaway
  re-send ([ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md)), which
  lies outside `retry-limit`. The attempt-accounting stage refuses the entry past that bound as a
  retry exhaustion that names the stage. Every `request-model` step's retry authority counts in the
  compiled retry-derived execution allowance, including each attempt's one runaway re-send, as the
  attempt-accounting step it replaced did (not yet implemented: the compiler skips these steps
  today). An ordinary-scope request that a workflow revisits starts a new request assignment,
  which restarts the attempt count, so across visits only this allowance and native iteration
  bound it. The stage bound above is separate from that allowance.
- **Events.** Every event of a stage names the stage (its dashed `Stage` name in `step_id`). The
  step's own start and end events name none, except that a failed end names the stage that ended
  the request. Retry exhaustion names the step and the stage.

## Accounting integration

- The explicitly selected `advance-model-attempt-accounting` step consumes the prepared
  request and declares `retry-limit` (`0` permits only its initial execution and ADR
  0039's runaway re-send, which accounting reserves with its own count, one per attempt,
  outside `retry-limit`).
- The compiler retains its accounting permission from the registered contract; YAML
  never authors it.
- The runner supplies read-only ledger snapshots and initial/retry classification,
  validates the proposed transition, and publishes sealed `accounted_model_attempt`
  evidence from the applied record together with the envelope delta.
- The runner owns retry counts: operation/immutable-assignment counts for ordinary
  requests, also bound to a pending native parent for dependent requests, and
  operation/native-defect counts for atomic repairs under
  [§22.7](22-repair.md#227-repair-retry-limit-and-escalation). Other retry-capable
  operations retain invocation-wide counts. Request ordinals never become a second
  retry counter or reset history.
- Retry authority names the accounting step, not the request origin.
- Consumers retain that original request and must invalidate consumed attempt evidence
  before a YAML retry revisits the accounting step.
- Foreign or stale evidence and a second initial attempt cannot reset an existing
  request's accounting.

- That accounting step is the sole attempt limit on the model-request correction path.
- The protocol-retry builder only prepares a corrected request from retained original
  inputs and the latest rejection; it has no separate execution limit.
- Runner exhaustion retains the compiled owner, limit and consumed execution count as a
  terminal rejection.

- The attempt and provider-operation ledgers share the request's fresh execution
  identity and have one cleanup owner; they are destroyed with the execution.
- Rejected deltas publish neither accounting changes nor attempt evidence.
- No provider call, lifecycle advancement, lease preparation or token charge is hidden
  in this integration.

## Operation assignment integration

- Parameter-free `assign-provider-operation` consumes the same prepared request and
  applied attempt.
- The existing lifecycle action proposes one inference assignment.
- The runner validates the exact retained request/attempt/binding/input association and
  current revisions, then publishes the immutable ledger successor and sealed
  `assigned_provider_operation` evidence from the applied canonical record with the
  envelope delta.
- The evidence retains the operation and request owners.
- Rejected deltas publish neither; consuming evidence does not remove an open operation.
- No authorization preparation, API call, retry, token charge or persistence is
  implicit.
- Later lifecycle phases use the separate YAML operations described below.

## Authorization preparation integration

- Authorization preparation is also integrated through the existing
  `prepare-provider-operation-authorization` action and runner-private lease table.
- The step takes no parameters, and compilation rejects a YAML `timeout-ms`. The
  deadline is the bound catalogue entry's required `requestTimeoutMs`
  ([§9](09-configuration.md)); the runner binds it to the exact retained request,
  attempt, assignment, model and input, and to every provider operation of that
  request, including protocol corrections.
- The runner derives one absolute monotonic deadline, allocates the existing private
  lease slot and validates exact result correlation before publication.
- The separately policy-permitted `provider-authorization` port can prepare only from
  preloaded state, without I/O, refresh or a model call.
- Its sealed result retains only an opaque lease reference or closed
  failure/cancellation facts.
- The runner validates publication and consumers, releases rejected/expired leases and
  destroys remaining capabilities at execution cleanup.
- No additional ledger, persisted handoff, implicit retry or token charge is introduced.

## Request invocation-state integration

- Request invocation state is integrated by `advance-model-request-lifecycle` with
  explicit `transition: invoked`.
- The existing action creates the immutable `assigned -> invoked` successor; only
  validated runner publication makes it current.
- Request-ledger replacements are checked at their shared boundary: assignment and
  lifecycle changes cannot impersonate each other, skip revisions or change another
  request.
- The runner retains the exact applied snapshot while all
  request/binding/resource/attempt/lease references stay unchanged.
- Prepared authorization is required and rechecked; cancellation or rejected publication
  leaves the prior ledger current.
- The provider operation stays assigned and no API call, token charge, new limit or
  persistence occurs.
- Request terminalization and the provider call use the separate explicit operations
  below.

## Provider-operation invocation-state integration

- `advance-provider-operation-lifecycle` with `transition: invoked` reuses the existing
  action for one assigned operation under an already-invoked request.
- The runner supplies the existing prepared lease's original deadline, checks the exact
  transition and authorization before publication, then publishes sealed
  invoked-operation evidence and invalidates assignment evidence together.
- The evidence references the canonical invocation and retains its owners.
- Failed, expired, cancelled, foreign, stale, duplicate or deadline-altered inputs
  reject without publication.
- The lease is not consumed here; `invoke-model` performs the separate call.
- Observed inference completion and pre-call termination use their separate explicit
  operations below.
- No additional capability, timeout, retry, token charge, persistence or recovery
  mechanism is introduced.

## Inference integration

- `invoke-model` consumes the same request, applied attempt, invoked operation and
  single-use lease without selection parameters.
- It performs one interface call and retains its untrusted observation or cancellation.
- The runner uses the shared association/usage validator and existing token ledger,
  accounting before result publication, cancellation or deadline rejection.
- Allocation for bookkeeping is done before the call, without token reservation or a
  size limit.
- Typed budget rejections reach the workflow caller and CLI; no YAML edge can bypass
  them.
- Complete, stopped, failed and cancelled results stay distinct.
- Decoding, terminalization and retries are not hidden inside invocation.
- Native composition requires an explicitly bound provider; fake implementations remain
  test-only.

## Observation validation integration

- `validate-provider-invocation-observation` is a parameter-free pure YAML step.
- It consumes the retained raw result and exact request/attempt/invocation inputs; the
  runner supplies the current call association without an authorization lease or
  operational capability.
- The existing validator alone proves association, usage consistency and UTF-8 safety.
- The result retains the existing immutable request and response values, keeping
  borrowed evidence valid without copying content.
- Complete, stopped, provider-failed, rejected and cancelled results stay distinct.
- Only complete evidence exposes decoder input.
- No token reconciliation, decoding, schema validation, retry or terminalization is
  implicit.

## Response admission: decoding and payload-schema validation

Decoding and payload-schema validation are one stage, `admit-model-response`; there is no separate
decode or schema stage. The decoder (`model_envelope.decode`) and the schema validator
(`model_payload_schema.validate`) are domain functions that only this stage calls.

- **Decoding.** The stage parses only the complete branch of the sealed observation through the
  existing decoder, and retains the source value with the owned tree. Syntax rejection, after the
  sole [§22.6](22-repair.md#226-unparseable-output) prefix normalization, returns typed
  `InvalidModelEnvelope` as `invalid`. Stops, failures, observation rejection and cancellation are
  forwarded unchanged without parsing; ADR 0039's runaway mapping (below) is applied here, not by
  the decoder. No schema check, new identity, byte limit, token charge, retry or lifecycle
  transition is introduced by decoding.
- **Schema validation.** The existing validator alone checks the decoded candidate against its
  original compiled schema. The owned result retains the source, publishing schema-valid evidence or
  a closed schema rejection; non-decoded protocol, provider and cancellation facts pass through
  unchanged. Consumers cannot substitute a schema or reuse foreign evidence. No parsing, copying of
  content, token charge, lifecycle transition or retry occurs, and schema validity stays distinct
  from semantic correctness and commit authority.
- **Contract.** `admit-model-response` is a parameter-free pure stage. It consumes the current
  request ledger, prepared request and sealed observation.
- The existing decoder parses complete evidence once; the existing schema
  validator checks that exact candidate against its retained selected schema.
  Shared result owners publish the existing envelope and payload keys together;
  payload evidence retains the exact envelope and original observation.
- The shared registered/compiled contract permits exactly this output pair with
  the decoder prerequisites and existing pure-response restrictions. Other
  response operations retain their single-output contracts.
- Syntax/schema diagnostics and non-complete outcomes remain distinct, except a
  provider `output_limit` stop: a first runaway (valid usage, on an attempt that is not
  a re-send) admits as `invalid` with no candidate, and a runaway on a re-send admits
  as `failed` with `RunawayRepeated`
  ([ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md)). Failure
  before publication releases both values. One delta-application/cancellation
  boundary replaces two; current-authority dependencies remain required.
- No new identity, schema selection, provider call, retry, accounting, semantic authority
  or runtime coordinator is introduced. Correction and closure are the next stages of the same
  step; retirement is the workflow's release step.

## Provider-operation completion integration

- `complete-provider-operation` is a parameter-free binding of the existing lifecycle
  action.
- It requires the prepared request, current request ledger, applied attempt, invoked
  operation and validated observation result.
- Complete output, provider stops and failures supply their exact terminal facts;
  cancellation without delivery evidence retains `accepted_or_unknown`.
- Rejected observation evidence cannot authorize completion.
- YAML cannot assert an outcome or delivery disposition.

- The runner checks the exact proposed fact and outcome, then publishes a sealed view of
  the canonical terminal record and invalidates invocation evidence in one application.
- It reuses the existing ledger and lease cleanup; response owners and token accounting
  do not change.
- Stops/failures stay `failed` and cancellation stays `cancelled`; provider completion
  proves no payload, logical request or workflow success.
- Completion may precede decoding, whose dependencies retain the original evidence.
- A runtime/budget rejection abandons execution without inserting a hidden completion
  step.

## Pre-call operation termination integration

- `terminate-provider-operation` is a parameter-free binding of the existing provider
  lifecycle action.
- It consumes the request ledger, prepared request, applied attempt, assigned operation
  and retained authorization result.
- A failure becomes `preparation_failed` with unchanged facts; cancellation becomes
  `cancelled(not_sent)`.
- The existing authorization validator owns failure association, delivery and retry
  consistency.
- Prepared authorization is rejected.

- The runner shares terminal publication with observed completion, using an exact
  assigned or invoked source.
- It validates the source, proposed terminal fact and outcome before publishing the
  successor and sealed terminal evidence together with assignment invalidation.
- Missing/foreign/stale/duplicate evidence and forged deltas reject without mutation.
- Consumers may retain authorization facts against exactly one current lifecycle phase,
  including terminal, without a clock for non-prepared outcomes; prepared lease checks
  are unchanged.

- The original result and request/attempt remain intact.
- Existing lease cleanup destroys backing once; no provider call, token charge, retry,
  persistence or logical-request transition is introduced by this operation.
- Request closure uses the explicit binding below.
- Runtime cancellation abandons execution without a hidden step.

## Logical-request closure integration

- `complete-model-request` is a parameter-free binding of
  `AdvanceModelRequestLifecycleAction`.
- It requires the current request ledger, prepared request, applied attempt, canonical
  terminal provider-operation evidence and retained payload-schema result.
- Every associated provider operation must be terminal before the runner can publish one
  direct `invoked -> terminal` request ledger successor.
- Response owners and actual-token accounting remain unchanged.

- Schema-valid evidence closes this request as `accepted` with `ok`; this accepts only a
  candidate, not semantics, user approval, commit or workflow success.
- Protocol/schema rejection closes as `failed` with `invalid`; provider stops or
  failures close as `failed` with `failed`; cancellation stays `cancelled`. An
  `output_limit` stop first admits as `invalid` and takes its one re-send through
  `check-model-runaway` and `build-model-runaway-resend`
  ([ADR 0039](../decisions/0039-configured-temperatures-and-runaway-resend.md)); only a
  runaway on the re-send closes as `failed`.
- The approved missing-final-answer case also admits as `invalid`, with no candidate:
  sealed observation evidence must establish `missing_final_text`, valid association
  and known usage. It may enter the same explicit protocol correction and attempt
  retirement path, or close as failed.
- The original detailed evidence is retained.
- Explicitly closing invalid content does not assert retry exhaustion; YAML may instead
  select permitted retry work before closure.
- Unsupported terminal reasons cannot be supplied as parameters.

- Missing, foreign, stale, duplicate, open-operation or forged reason/outcome evidence
  cannot replace the ledger.
- The runner independently validates the successor and retains the exact published
  snapshot, without a second ledger, capability, call, lease renewal, token charge or
  persistence.
- Pure closure needs no remaining token budget or unexpired provider deadline; runtime
  cancellation still abandons execution without inserting a hidden closure step.

## Pre-call logical-request closure integration

- `terminate-model-request` is a parameter-free binding of
  `AdvanceModelRequestLifecycleAction`.
- It requires the current request ledger, prepared request, applied attempt, terminal
  operation and retained authorization result.
- The existing authorization validator checks exact identity and matching terminal
  facts.
- Failure closes an assigned request as `not_invoked_authorization_failure` or an
  invoked request as `failed`; cancellation closes either as `cancelled`.
- YAML outcomes remain `failed` or `cancelled`; prepared authorization cannot authorize
  closure.

- Every associated operation must be terminal.
- The shared runner replacement validator rejects missing, foreign, stale, duplicate,
  inconsistent or forged evidence before publishing the direct request-ledger successor.
- Original evidence ownership, lease cleanup and token accounting are unchanged.
- No response, capability, live lease, clock, provider call, retry or persistence is
  added.
- Runtime abandonment never inserts this step or infers workflow success.
