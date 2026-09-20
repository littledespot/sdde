# ADR 0018: Capture complete model exchanges at debug level

- **Status:** Accepted
- **Date:** 2026-09-19
- **Decision authority:** Explicit user direction that debug logging retain every full LLM prompt and output for tuning, including the production execution path.
- **Amends:** Design §§9, 13.4, 26.5, 27, 31.8 and 31.34; F0001's logging configuration, F0002's capture/sanitization/verification contracts and F0006's provider observation boundary.

## Decision

Setting `logs.level` to `debug` or the more verbose `trace` enables complete
request and response body capture for every production model invocation attempt.
The shared effective logging policy selects both directions and every body class
at these levels. Higher thresholds emit metadata only. The closed `logs` object
contains `level` and `console`; the superseded `promptCapture` field is removed and
rejected, with no compatibility reader or migration. Since debug/trace selects all
bodies and higher thresholds exclude the registered debug prompt rows, retaining
direction/class switches would leave configuration with no effect.
The governing design retains its Proposed status.

Capture the full model-facing request after assembly, including system/task
instructions, response-format guidance, schema, reference inputs and code inputs.
Attempt capture of each available returned model body before JSON/envelope/schema admission,
so malformed or rejected outputs and outputs on failed provider attempts remain
inspectable. Retries are separate attributed exchanges. An attempt with no
returned body records a typed `transport_outcome` diagnostic; it does not invent an
empty provider response as evidence of delivery. Requests are persisted before provider dispatch, and
returned bodies are captured before they can be discarded on any terminal path.
If response logging fails, provider decoding and actual-usage accounting still run
before the invocation blocks; the failure cannot release a candidate or permit
another business operation.

Every exchange retains its feature/run/workflow, request, model-operation/slot,
direction and attempt association. This is a shared production invocation
boundary, not an E2E-only wrapper or a workflow-specific branch. Logs remain
observations; body capture grants no candidate, retry, state or completion authority.
The existing wire columns retain their names: `route_id` identifies the model
operation and `model_profile_id` identifies the repository slot in prompt rows.
`request_id` derives from the current request-ledger ordinal; attempt ordinals
retain the invocation's `u32` domain without narrowing.

Composition injects a narrow observation port into the provider adapter. The common
runner binds its request identity and lifetime before invoking the action. The
adapter may submit only borrowed body bytes, typed provenance and credential values
needed for redaction; it receives no logger, log-sink, child binding, action selector
or workflow transition capability. The execution-owned capture runner and active
logging lifecycle retain the fixed logging orchestration under §13.9. Actions and
the model receive no capture or child-execution capability. This does not amend the
action/orchestrator invariants or give the provider control of a business graph.

## Production activation and finalization

The selected graph requests `activate-feature-logging` after deterministic target
and reference preflight and before the first model request. The operation is
registered for any feature-scoped workflow; the generic engine has no workflow-name
branch. Composition owns the logging adapters and their lifetime. A fresh log run
uses an engine-generated random ID, a binding ordinal and a fingerprint of the
validated compiled logging policy. These identify observations, not workflow state.

Activation rechecks the bootstrap root and selected feature observations using
no-follow descriptor access. It may create the observed-absent paths, then returns
an owned run-local active-directory capability and publishes a distinct activated-directory
observation, preserving preflight facts and their dependent evidence. Readers, protected-input rechecks, publication and the log registry
consume that exact capability; bootstrap observations remain immutable. Stale,
foreign, replaced and aliased paths reject. Existing run IDs reject rather than
reusing a previous run. Log run/binding directories are owner-only, and the sink
continues to require an already activated layout.

The runner finalizes logging before invoking an operation with the registered
`workflow_publication` effect. A close failure therefore blocks before any output
or successful completion-state write. The engine's common terminal binding also
finalizes on failures, cancellation and outcomes without publication; repeated
finalization is idempotent and preserves an existing failure. Cleanup releases
owners only after the finalization result has contributed to the reported outcome.
Publication is terminal in the compiled graph: prepared output carries the validated
`ok` or `needs_user` outcome, and each publication edge targets that terminal directly.
This also excludes pure post-publication steps that could emit telemetry or fail
after the required log stream has closed.

The user-approved R39 clarification (20 September 2026) retains this ordering.
Before close, persist `publication.prepared` with the validated intended outcome.
Actual write success/failure is reported by the existing terminal result and harness
report, not the closed feature log. Execution, admission, repair and retry events
use the existing registry and barrier; retry counts are projections of runner state.
For paths without publication, persist the terminal event before close. No logged
intent grants completion and no post-write logging failure can rewrite completion
history. Pre-activation failures retain the terminal/emergency path.

This run-local lifecycle does not restore the persisted bootstrap-policy lineage,
WAL or historical execution recovery withdrawn by ADR 0009. Earlier historical
maintenance catalogue entries are not current-run activation prerequisites. Old
logs remain observations and are never read as workflow continuation authority.

## Content and storage

Credential redaction remains mandatory. Authentication headers, credential
configuration and environment secrets are not model-facing prompt content and
must not be added to capture. The production boundary removes exact credential
values held by the invocation's authorization, including their JSON-escaped forms,
before content is split. Fixed markers expose neither the original value nor its
length. This does not claim detection of arbitrary unknown secrets embedded in
reference text or model output; the existing classified-fragment sanitization
contract remains separate.

The typed `complete_body` capture class retains the complete serialized model-facing
request/returned body after redaction. It need not parse a malformed model response
into typed content merely to log it. `complete_body` is an internal body class,
not a configuration selector. A closed capture-body variant distinguishes actual
`provider_body` bytes, an incomplete received prefix (`partial_provider_body`),
and an engine-authored `transport_outcome` diagnostic. Transport failures retain
all body bytes already received, including truncated framing, rejected response
headers, cancellation and deadlines. A partial prefix is never represented as a
complete provider response. Retaining it does not change the original transport
failure, delivery classification or retry policy.

The 5,000-byte sanitized fragment size is a row/chunk bound, not an exchange-size
ceiling. Split valid UTF-8 sanitized bodies at scalar boundaries into deterministically
ordered fragments. Invalid UTF-8 bodies use complete base64 capture with the encoding
identified in each fragment ID. Engine-owned fragment IDs encode operation kind,
direction, body provenance, encoding and zero-padded byte offset, sufficient to
reconstruct content and distinguish complete bodies, partial prefixes and transport
diagnostics. `truncated=false` means the logger retained all available bytes; the
`partial_provider_body` provenance still identifies incomplete transport framing.
Never silently truncate, drop the tail, summarize or select only successful
payloads. Redaction is the only authorized content removal. No local model-call
limit is introduced; ADR 0011 remains unchanged.

Reuse the registered feature prompt stream, format, sequence, locking, permissions,
rotation, retention and flush rules. File writes remain mandatory; console output
is only a mirror. If sanitization, serialization, chunk persistence or existing
segment capacity fails, follow the existing fail-closed logging failure path.
Partial logs may remain after a failure, but no success may claim that the entire
exchange was captured. No alternative sink, best-effort fallback or recovery
continuation is introduced.

## Acceptance criteria

- `debug` and `trace` capture full requests and responses through the production
  invocation path and across unrelated
  workflow operations and model slots.
- Higher thresholds emit metadata only; the removed `promptCapture` field rejects.
- Each dispatched attempt retains its exact assembled request and each available
  raw returned body, including protocol/schema rejection, retries and provider
  failure after a body was returned. No-response failures remain distinguishable.
- Content longer than 5,000 bytes, multibyte/invalid UTF-8 text, escaped delimiters and secrets
  crossing would-be chunk boundaries prove complete reconstruction after redaction.
- Authorized credential redaction and metadata-only event records remain enforced;
  no-body diagnostics cannot be mistaken for actual returned provider bytes.
- Capture failures, segment exhaustion and cleanup retain existing fail-closed
  semantics. Captured content never becomes workflow or completion authority.
- Fresh and existing targets activate the real file sink before model dispatch; stale
  observations and unsafe paths block. Every terminal path closes the sink, and
  close failure prevents publication.
- Offline tests and native clean-environment packaging checks establish production
  wiring. Live E2E execution remains separately authorized and separately reported.
