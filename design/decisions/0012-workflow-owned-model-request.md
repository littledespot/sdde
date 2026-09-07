# ADR 0012: Retain one workflow-owned model request across YAML steps

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Explicit user direction
- **Amends:** Design Sections 7.3 and 12, ADRs 0004/0005, and F0005/F0006

## Decision

A generic request belongs to its current execution, originating compiled YAML
step and request ordinal. It does not require a fabricated SDD feature, section
or task. Existing SDD owner variants and purpose validation remain required by
operations that use those domain authorities; generic ownership cannot stand
in for semantic-review, repair or clarification authority.

The originating step declares the repository slot, response controls, prompt,
result schema and optional input resource once. Separate registered identity,
binding-validation and request-building operations exchange immutable typed
pipeline values. Consumers retain the originating request identity, binding,
resources and content; they do not rebind to their own step or repeat selection
parameters. The existing data-dependency compiler proves the required handoff.
There is no new route registry, implicit graph or YAML transport syntax.
The internal request content contract is `model-request/v1`; it is not a second
YAML schema resource. Prompt content and the result schema remain explicitly
workflow-selected, never packaged defaults.

[ADR 0013](0013-workflow-input-reuse.md) adds the optional originating parameter
`result-selection: input` (default `resource`). It resolves the native packet's
typed result-definition ID within the explicitly bound schema resource once.
Missing packets, selectors or complete result definitions fail before invocation.
The selector is internal; consumers retain the selected compiled schema through
validation, retries and completion. No model-owned field selects its schema.

Only a typed slot selects a new model binding. A registered consumer of the
prepared-request data contract can use its retained binding instead. Provider
capabilities still derive from narrow ports, require policy permission and do
not follow merely from access to immutable request data. A consumer cannot also
select another slot, resource or response control for that request.

Request-ledger initialization creates a fresh process-local execution identity.
The runner owns every value and applies or discards each delta; shared canonical
identity owners remain alive until their last consumer is destroyed. Neither
identities nor prepared requests are persisted, restored or reused by a rerun.
No provider invocation, counting, retry or successor selection occurs during
request preparation. ADRs 0009 and 0011 remain unchanged.

Native sealed pipeline values may omit a byte cap when their owning contract
has none. Their ownership transfer remains typed and opaque; ordinary copying
values and contracts with explicit resource bounds retain their existing checks.
This is not a second request store or a model-call size policy.

## Accounting integration (implemented 2026-09-06)

The explicitly selected `advance-model-attempt-accounting` step consumes the
prepared request and declares `retry-limit` (`0` permits only its initial
execution). The compiler retains its accounting permission. The runner supplies
read-only ledger snapshots and initial/retry classification, validates the
proposed transition, and publishes sealed evidence from the applied record.
Its existing step-execution counter alone supplies retries used; request
ordinals never become a second retry counter. Retry authority names the
accounting step, not the request origin. Consumers retain that original request
and must invalidate consumed attempt evidence before a YAML retry revisits the
accounting step. A second initial attempt cannot reset an existing request.

The attempt and provider-operation ledgers share the request execution identity
and have one cleanup owner. Rejected deltas publish neither accounting changes
nor attempt evidence. No provider call, lifecycle advancement, lease preparation
or token charge is hidden in this integration.

## Operation assignment integration (implemented 2026-09-06)

`assign-provider-operation` consumes the same prepared request and applied
attempt; `kind` explicitly selects `inference` or `input-token-count`. The existing
lifecycle action proposes one assignment. The runner validates the exact retained
association and publishes sealed evidence from the applied canonical record with
the envelope delta. The evidence retains the operation and request owners.
Rejected deltas publish neither; consuming evidence does not remove an open
operation. No authorization preparation, API call, retry, token charge or
persistence is implicit. Later lifecycle phases use the separate YAML operations
described below.

## Authorization preparation integration (implemented 2026-09-06)

Authorization preparation is also integrated through the existing
`prepare-provider-operation-authorization` action and runner-private lease
table. YAML supplies only explicit positive `timeout-ms`; the runner binds the
deadline to the exact retained request, attempt, assignment, model and input.
The separately policy-permitted `provider-authorization` port can prepare only
from preloaded state, without I/O, refresh or a model call. Its sealed result
retains only an opaque lease reference or closed failure/cancellation facts.
The runner validates publication and consumers, releases rejected/expired
leases and destroys remaining capabilities at execution cleanup. No additional
ledger, persisted handoff, implicit retry or token charge is introduced.

## Request invocation-state integration (implemented 2026-09-06)

Request invocation state is integrated by `advance-model-request-lifecycle`
with explicit `transition: invoked`. The existing action creates the immutable
`assigned -> invoked` successor; only validated runner publication makes it
current. Request-ledger replacements are checked at their shared boundary:
assignment and lifecycle changes cannot impersonate each other, skip revisions
or change another request. The runner retains the exact applied snapshot while
all request/binding/resource/attempt/lease references stay unchanged. Prepared
authorization is required and rechecked; cancellation or rejected publication
leaves the prior ledger current. The provider operation stays assigned and no
API call, token charge, new limit or persistence occurs. Request terminalization
and the provider call use the separate explicit operations below.

## Provider-operation invocation-state integration (implemented 2026-09-06)

`advance-provider-operation-lifecycle` with `transition: invoked` reuses the
existing action for one assigned operation under an already-invoked request.
The runner supplies the existing prepared lease's original deadline, checks
the exact transition and authorization before publication, then publishes
sealed invoked-operation evidence and invalidates assignment evidence together.
The evidence references the canonical invocation and retains its owners.
Failed, expired, cancelled, foreign, stale, duplicate or deadline-altered inputs
reject without publication. The lease is not consumed here; `invoke-model`
performs the separate call. Observed inference completion is now explicit below;
pre-call termination uses its separate explicit operation below. No additional capability,
timeout, retry, token charge, persistence or recovery mechanism is introduced.

## Inference integration (implemented 2026-09-06)

`invoke-model` consumes the same request, applied attempt, invoked operation and
single-use lease without selection parameters. It performs one interface call
and retains its untrusted observation or cancellation. The runner uses the shared
association/usage validator and existing token ledger, accounting before result
publication, cancellation or deadline rejection. Allocation for bookkeeping is
done before the call, without token reservation or a size limit. Typed budget
rejections reach the workflow caller and CLI; no YAML edge can bypass them.
Complete, stopped, failed and cancelled results stay distinct. Decoding,
terminalization and retries are not hidden inside invocation. Native composition
requires an explicitly bound provider; fake implementations remain test-only.

## Observation validation integration (implemented 2026-09-06)

`validate-provider-invocation-observation` is a parameter-free pure YAML step.
It consumes the retained raw result and exact request/attempt/invocation inputs;
the runner supplies the current call association without an authorization lease
or operational capability. The existing validator alone proves association,
usage consistency and UTF-8 safety. The result retains the existing immutable
request and response values, keeping borrowed evidence valid without copying
content. Complete, stopped, provider-failed, rejected and cancelled results stay
distinct. Only complete evidence exposes decoder input. No token reconciliation,
decoding, schema validation, retry or terminalization is implicit.

## JSON decoding integration (implemented 2026-09-06)

Native `decode-model-envelope` is also integrated as a parameter-free pure step.
It consumes the same prepared request and sealed observation, parses only its
complete branch through the existing decoder, and retains the source value with
the owned tree. Syntax rejection returns typed `InvalidModelEnvelope` as
`invalid`; the inference profile now permits `end.invalid`, preserving the
compiler's matching-terminal rule. Stops, failures, observation rejection and
cancellation are forwarded unchanged without parsing. No schema check, new
identity, byte limit, token charge, retry or lifecycle transition is introduced.

## Payload-schema validation integration (implemented 2026-09-06)

`validate-model-payload-schema` is a parameter-free pure step consuming the
retained decoded result, prepared request and request ledger. The existing
validator alone checks decoded candidates against their original compiled schema.
Its owned result retains the source, publishing schema-valid evidence or a closed
schema rejection; non-decoded protocol/provider/cancellation facts pass through
unchanged. Consumers cannot substitute a schema or reuse foreign evidence.
No parsing, copying of content, token charge, lifecycle transition or retry occurs.
Schema validity remains distinct from semantic correctness and commit authority.

## Provider-operation completion integration (implemented 2026-09-06)

`complete-provider-operation` is a parameter-free binding of the existing
lifecycle action. It requires the prepared request, current request ledger,
applied attempt, invoked operation and validated observation result. Complete
output, provider stops and failures supply their exact terminal facts;
cancellation without delivery evidence retains `accepted_or_unknown`. Rejected
observation evidence cannot authorize completion. YAML cannot assert an outcome
or delivery disposition.

The runner checks the exact proposed fact and outcome, then publishes a sealed
view of the canonical terminal record and invalidates invocation evidence in
one application. It reuses the existing ledger and lease cleanup; response
owners and token accounting do not change. Stops/failures stay `failed` and
cancellation stays `cancelled`; provider completion proves no payload, logical
request or workflow success. Completion may precede decoding, whose dependencies
retain the original evidence. A runtime/budget rejection
abandons execution without inserting a hidden completion step.

Count integration uses the same ownership and lifecycle mechanisms.
`count-model-input-tokens` retains the original request/binding with its raw
result; `validate-model-token-count-observation` retains those owners with
validated count/failure facts or distinct rejection/cancellation.
`complete-count-operation` consumes this exact evidence through the existing
provider lifecycle action. `complete-count-request` closes only failed/cancelled
requests after every associated operation is terminal; count success cannot
accept a logical request. These parameter-free bindings add no count prerequisite,
capacity gate, token charge, retry authority or completion ledger.

## Pre-call operation termination integration (implemented 2026-09-06)

`terminate-provider-operation` is a parameter-free binding of the existing
provider lifecycle action. It consumes the request ledger, prepared request,
applied attempt, assigned operation and retained authorization result. A failure
becomes `preparation_failed` with unchanged facts; cancellation becomes
`cancelled(not_sent)`. The existing authorization validator owns failure
association, delivery and retry consistency. Prepared authorization is rejected.

The runner shares terminal publication with observed completion, using an exact
assigned or invoked source. It validates the source, proposed terminal fact and
outcome before publishing the successor and sealed terminal evidence together
with assignment invalidation. Missing/foreign/stale/duplicate evidence and
forged deltas reject without mutation. Consumers may retain authorization facts
against exactly one current lifecycle phase, including terminal, without a
clock for non-prepared outcomes; prepared lease checks are unchanged.

The original result and request/attempt remain intact. Existing lease cleanup
destroys backing once; no provider call, token charge, retry, persistence or
logical-request transition is introduced by this operation. Request closure uses
the explicit binding below. Runtime cancellation abandons execution without a hidden step.

## Logical-request closure integration (implemented 2026-09-06)

`complete-model-request` is a parameter-free binding of
`AdvanceModelRequestLifecycleAction`. It requires the current request ledger,
prepared request, applied attempt, canonical terminal provider-operation evidence
and retained payload-schema result. Every associated provider operation must be
terminal before the runner can publish one direct `invoked -> terminal` request
ledger successor. Response owners and actual-token accounting remain unchanged.

Schema-valid evidence closes this request as `accepted` with `ok`; this accepts
only a candidate, not semantics, user approval, commit or workflow success.
Protocol/schema rejection closes as `failed` with `invalid`; provider stops or
failures close as `failed` with `failed`; cancellation stays `cancelled`.
The original detailed evidence is retained. Explicitly closing invalid content
does not assert retry exhaustion; YAML may instead select permitted retry work
before closure. Unsupported terminal reasons cannot be supplied as parameters.

Missing, foreign, stale, duplicate, open-operation or forged reason/outcome
evidence cannot replace the ledger. The runner independently validates the
successor and retains the exact published snapshot, without a second ledger,
capability, call, lease renewal, token charge or persistence. Pure closure needs
no remaining token budget or unexpired provider deadline; runtime cancellation
still abandons execution without inserting a hidden closure step.

## Pre-call logical-request closure integration (implemented 2026-09-06)

`terminate-model-request` is a parameter-free binding of
`AdvanceModelRequestLifecycleAction`. It requires the current request ledger,
prepared request, applied attempt, terminal operation and retained authorization
result. The existing authorization validator checks exact identity and matching
terminal facts. Failure closes an assigned request as
`not_invoked_authorization_failure` or an invoked request as `failed`;
cancellation closes either as `cancelled`. YAML outcomes remain `failed` or
`cancelled`; prepared authorization cannot authorize closure.

Every associated operation must be terminal. The shared runner replacement
validator rejects missing, foreign, stale, duplicate, inconsistent or forged
evidence before publishing the direct request-ledger successor. Original evidence
ownership, lease cleanup and token accounting are unchanged. No response,
capability, live lease, clock, provider call, retry or persistence is added.
Runtime abandonment never inserts this step or infers workflow success.

## Acceptance

Compile and execute arbitrary YAML using the native preparation bindings and
test-only provider contracts. Prove exact identity/resource retention across
different steps, missing-input and rebinding rejection, malformed SDD owners,
cancellation, allocation cleanup and isolation between executions. Test-only
assignment cases also cover duplicate/open operations, both kinds, stale/foreign
evidence, forged transitions and compiler-permission tampering. Authorization
cases cover both operation kinds, missing/invalid deadlines, denied capability,
failed preparation, forged/mismatched deposits and results, duplicate use,
expiration, cancellation and allocation-failure cleanup. Test-only
provider contracts do not enter production composition. Invocation-state cases
also prove exact canonical evidence, the unchanged lease deadline, one-use
consumption through the existing adapter port, rejected-delta atomicity and
execution isolation. Fake-provider YAML tests also cover one inference call,
lease reuse, missing dependencies/capabilities, original deadlines, actual-token
accounting, failed publication, allocation cleanup and execution isolation.
Observation-validation cases cover exact associations, every stop, provider
failures, cancellation, invalid UTF-8, cross-execution rejection, missing inputs,
parameter overrides, allocation cleanup and retained evidence lifetime. Token
usage is unchanged, and pure validation remains available at budget exhaustion.
Decoder cases cover valid objects, exact numbers, malformed JSON, duplicate
decoded keys, trailing content, missing/foreign evidence, source-owner lifetime,
allocation failure and rejected/cancelled publication. Payload-validation cases
cover exact compiled schemas, accepted/rejected candidates, unchanged upstream
outcomes, missing/foreign evidence, overrides, owner lifetime, allocation failure,
cancelled/rejected publication and validation at token-budget exhaustion.
Completion cases cover exact terminal facts, malformed/schema-invalid content
independence, missing/foreign/stale/duplicate evidence, forged facts/outcomes,
allocation/cancellation cleanup, owner lifetime and unchanged usage at exhaustion.
Request-closure cases cover all evidence-backed reasons/outcomes, unfinished
operations, missing/foreign/stale/duplicate inputs, forged successors/reasons,
suppressed failures, compiler/registry rejection, allocation and cancellation
cleanup, owner lifetime, and closure without a live lease at token exhaustion.
Production Bedrock is connected through the same retained-request bindings;
shared fake/adapter and YAML tests prove the production handoff.

Pre-call termination cases cover both operation kinds, failure/cancellation,
prepared/missing/foreign/stale/duplicate rejection, forged deltas, no-clock
terminal fact consumption, prepared-lease checks, allocation and deposited-lease
cleanup, retained owners, and runtime abandonment without hidden termination.
Pre-call request-closure cases additionally cover both request statuses, exact
terminal reasons, unfinished operations, mismatched authorization/terminal facts,
forged request successors and outcomes, immutable ledger ownership, allocation
and cancellation cleanup, YAML assertions and compiled-contract tampering.
An inference-then-authorization-rejection YAML run preserves the earlier response
and token charge while closing the invoked request as failed or cancelled.
